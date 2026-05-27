//+------------------------------------------------------------------+
//|                                      DailyDirection_Pro_v1.mq5    |
//|   EA multi-mercado: direccion diaria (D1/H12/H8) + cruce 9/26     |
//|   en TF bajos + exits adaptativos por timeframe + sizing universal|
//|   Compilar en MetaEditor (MT5). Funciona en cualquier simbolo.    |
//+------------------------------------------------------------------+
#property copyright "DailyDirection Pro"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
CTrade        trade;
CPositionInfo pos;

//====================================================================
//  ENUMS
//====================================================================
enum ENUM_TF_MODE
{
   TFMODE_CURRENT = 0,  // Usar TF del grafico
   TFMODE_M1      = 1,
   TFMODE_M5      = 2,
   TFMODE_M15     = 3,
   TFMODE_M30     = 4,
   TFMODE_H1      = 5,
   TFMODE_H4      = 6
};
enum ENUM_CROSS_MODE
{
   CROSS_EITHER = 0,  // EMA o SMA (cualquiera) - DEFAULT
   CROSS_EMA    = 1,  // Solo EMA 9/26
   CROSS_SMA    = 2,  // Solo SMA 9/26
   CROSS_BOTH   = 3   // Ambos a la vez
};
enum ENUM_RISK_MODE
{
   RISK_PERCENT = 0,  // % de equity por trade
   RISK_FIXEDLOT= 1   // Lote fijo
};

//====================================================================
//  INPUTS
//====================================================================
input group "==== GENERAL ===="
input long          InpMagic            = 990011;   // Magic Number
input ENUM_TF_MODE  InpTFMode           = TFMODE_CURRENT; // Timeframe operativo
input int           InpMaxSpreadPts     = 60;       // Max spread (puntos)
input int           InpSlippagePts      = 30;       // Slippage (puntos)
input bool          InpAllowPyramid     = false;    // Permitir varias posiciones

input group "==== RIESGO / SIZING ===="
input ENUM_RISK_MODE InpRiskMode        = RISK_PERCENT; // Modo de riesgo
input double        InpRiskPercent      = 1.0;      // Riesgo % equity por trade
input double        InpFixedLot         = 0.01;     // Lote fijo (si modo lote fijo)
input double        InpMinAccountUSD    = 10.0;     // Capital minimo para operar
input double        InpMaxRiskCash      = 0.0;      // Cap riesgo USD (0=off)
input bool          InpCompound         = true;     // Compounding por equity

input group "==== DIRECCION DIARIA ===="
input int           InpConfidenceMin    = 65;       // Confianza minima (0-100)
input bool          InpUseH12           = true;     // Confirmar con H12
input bool          InpUseH8            = true;     // Confirmar con H8

input group "==== ENTRADA TF BAJO (cruce 9/26) ===="
input ENUM_CROSS_MODE InpCrossMode      = CROSS_EITHER; // Modo de cruce
input bool          InpUseSlopeFilter   = true;     // Filtro de pendiente
input bool          InpUseEntryADX      = true;     // Filtro ADX en entrada
input int           InpEntryADXMin      = 18;       // ADX minimo entrada

input group "==== EXITS / ATR ===="
input int           InpATRPeriod        = 14;       // Periodo ATR
input double        InpAggSL            = 1.5;      // Agresivo: SL = ATR x
input double        InpAggTP            = 2.5;      // Agresivo: TP = ATR x
input double        InpAggTrail         = 1.0;      // Agresivo: trail = ATR x
input double        InpAggPartialR      = 1.0;      // Agresivo: parcial en R
input double        InpAggPartialPct    = 50.0;     // Agresivo: % a cerrar
input double        InpPatSL            = 2.5;      // Paciente: SL = ATR x
input double        InpPatTP            = 5.0;      // Paciente: TP = ATR x
input double        InpPatTrail         = 2.0;      // Paciente: trail = ATR x

input group "==== PANEL ===="
input bool          InpShowPanel        = true;     // Mostrar panel
input int           InpPanelX           = 12;       // Panel X
input int           InpPanelY           = 22;       // Panel Y

//====================================================================
//  CONSTANTES / ESTADO
//====================================================================
#define PFX "DDP_"

enum ENUM_DIR { DIR_NONE=0, DIR_BULL=1, DIR_BEAR=-1 };
enum ENUM_PROFILE { PROF_AGGRESSIVE=0, PROF_PATIENT=1 };

ENUM_TIMEFRAMES g_opTF;        // TF operativo resuelto
ENUM_PROFILE    g_profile;     // perfil de salida
ENUM_DIR        g_dir = DIR_NONE;
int             g_conf = 0;    // confianza 0-100
int             g_voteBull=0, g_voteBear=0;
string          g_filterTxt = "";

// Handles direccion (D1)
int hEMA50_D1, hEMA200_D1, hADX_D1, hIchi_D1;
int hEMA50_H12=INVALID_HANDLE, hEMA50_H8=INVALID_HANDLE; // si nativo disponible
bool g_h12Native=false, g_h8Native=false;

// Handles entrada (TF operativo)
int hSMA9, hSMA26, hEMA9, hEMA26, hATR, hADX_op;

// Tracking dia / PnL
datetime g_curDay=0;
double   g_dailyPnL=0.0;
bool     g_hasOpenSpan=false;
int      g_winsToday=0, g_lossToday=0, g_tradesToday=0;

// rolling winrate (20)
int   g_wlBuf[20]; int g_wlIdx=0; int g_wlCount=0;

bool  g_isTester=false;
datetime g_lastEntryBar=0;
datetime g_lastDirBar=0;

//====================================================================
//  HELPERS BASE
//====================================================================
ENUM_TIMEFRAMES ResolveTF()
{
   switch(InpTFMode)
   {
      case TFMODE_M1:  return PERIOD_M1;
      case TFMODE_M5:  return PERIOD_M5;
      case TFMODE_M15: return PERIOD_M15;
      case TFMODE_M30: return PERIOD_M30;
      case TFMODE_H1:  return PERIOD_H1;
      case TFMODE_H4:  return PERIOD_H4;
      default:         return (ENUM_TIMEFRAMES)_Period;
   }
}

ENUM_PROFILE ResolveProfile(ENUM_TIMEFRAMES tf)
{
   // M1..M15 => agresivo ; M30+ => paciente
   if(PeriodSeconds(tf) <= PeriodSeconds(PERIOD_M15)) return PROF_AGGRESSIVE;
   return PROF_PATIENT;
}

ENUM_ORDER_TYPE_FILLING PickFilling(const string sym)
{
   uint m=(uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((m & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((m & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &store)
{
   datetime cur=iTime(_Symbol, tf, 0);
   if(cur!=store){ store=cur; return true; }
   return false;
}

int SpreadPts(){ return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

double NormalizeVolume(double v)
{
   double mn=SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st<=0) return 0;
   v=MathFloor(v/st)*st;
   if(v<mn) v=mn;
   if(v>mx) v=mx;
   return v;
}

int OpenPosCount()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic) c++;
   }
   return c;
}

double FloatingPnL()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic) p+=pos.Profit()+pos.Swap();
   }
   return p;
}

//====================================================================
//  H8 / H12 AGREGADO DESDE H1 (fallback)
//====================================================================
// Devuelve cierre/ema-slope direccion para TF agregado.
// out_slopeUp=true si EMA50 del TF agregado sube.
bool AggSlopeFromH1(int blockHours, bool &slopeUp)
{
   MqlRates h1[]; ArraySetAsSeries(h1,true);
   int need = 60*blockHours + blockHours; // ~60 velas agregadas para EMA50
   int got=CopyRates(_Symbol, PERIOD_H1, 0, need, h1);
   if(got<=0) return false;
   // construir cierres agregados (mas reciente primero)
   double closes[]; ArrayResize(closes,0);
   int i=0;
   while(i<got)
   {
      MqlDateTime dt; TimeToStruct(h1[i].time, dt);
      if(dt.hour % blockHours != 0){ i++; continue; }
      // h1[i] es apertura del bloque (mas reciente del bloque); cierre = h1[i] close si bloque incompleto
      double c = h1[i].close;
      int n=ArraySize(closes); ArrayResize(closes,n+1); closes[n]=c;
      i+=blockHours;
   }
   int m=ArraySize(closes);
   if(m<52) return false;
   // EMA50 sobre closes (closes[0]=mas reciente). EMA simple iterativa desde el mas viejo.
   double k=2.0/(50.0+1.0);
   double ema=closes[m-1];
   for(int j=m-2;j>=0;j--) ema = closes[j]*k + ema*(1.0-k);
   // pendiente: comparar ema actual vs ema hace ~3 velas agregadas
   double emaPrev=closes[m-1];
   for(int j=m-2;j>=3;j--) emaPrev = closes[j]*k + emaPrev*(1.0-k);
   slopeUp = (ema>emaPrev);
   return true;
}

//====================================================================
//  MOTOR DE DIRECCION DIARIA (confluencia ponderada)
//====================================================================
void ComputeDirection()
{
   g_voteBull=0; g_voteBear=0; g_conf=0; g_filterTxt="";
   string ft="";

   // --- Filtro 1: EMA50 vs EMA200 D1 + pendiente (peso 25) ---
   double e50[3], e200[1];
   if(CopyBuffer(hEMA50_D1,0,0,3,e50)==3 && CopyBuffer(hEMA200_D1,0,0,1,e200)==1)
   {
      bool up = (e50[0]>e200[0]) && (e50[0]>e50[2]);
      bool dn = (e50[0]<e200[0]) && (e50[0]<e50[2]);
      if(up){ g_voteBull+=25; ft+="EMA^ "; }
      else if(dn){ g_voteBear+=25; ft+="EMAv "; }
      else ft+="EMA- ";
   }

   // --- Filtro 2: ADX>25 + DI direccion D1 (peso 25) ---
   double adx[1], pdi[1], mdi[1];
   if(CopyBuffer(hADX_D1,0,0,1,adx)==1 &&
      CopyBuffer(hADX_D1,1,0,1,pdi)==1 &&
      CopyBuffer(hADX_D1,2,0,1,mdi)==1)
   {
      if(adx[0]>25.0)
      {
         if(pdi[0]>mdi[0]){ g_voteBull+=25; ft+="ADX^ "; }
         else            { g_voteBear+=25; ft+="ADXv "; }
      }
      else ft+="ADX- ";
   }

   // --- Filtro 3: Ichimoku nube D1 (peso 18) ---
   double spanA[1], spanB[1], cl[1];
   if(CopyBuffer(hIchi_D1,2,1,1,spanA)==1 &&   // SENKOU A (buffer 2)
      CopyBuffer(hIchi_D1,3,1,1,spanB)==1)     // SENKOU B (buffer 3)
   {
      cl[0]=iClose(_Symbol,PERIOD_D1,0);
      double top=MathMax(spanA[0],spanB[0]);
      double bot=MathMin(spanA[0],spanB[0]);
      if(cl[0]>top && spanA[0]>spanB[0]){ g_voteBull+=18; ft+="ICH^ "; }
      else if(cl[0]<bot && spanA[0]<spanB[0]){ g_voteBear+=18; ft+="ICHv "; }
      else ft+="ICH- ";
   }

   // --- Filtro 4: precio vs rango dia previo (peso 12) ---
   double pdh=iHigh(_Symbol,PERIOD_D1,1);
   double pdl=iLow(_Symbol,PERIOD_D1,1);
   double pdm=(pdh+pdl)/2.0;
   double px=iClose(_Symbol,PERIOD_D1,0);
   if(px>pdm){ g_voteBull+=12; ft+="PD^ "; }
   else if(px<pdm){ g_voteBear+=12; ft+="PDv "; }

   // --- Filtro 5: H12 slope (peso 12) ---
   if(InpUseH12)
   {
      bool up12=false; bool ok=false;
      if(g_h12Native && hEMA50_H12!=INVALID_HANDLE)
      {
         double h12[3];
         if(CopyBuffer(hEMA50_H12,0,0,3,h12)==3){ up12=(h12[0]>h12[2]); ok=true; }
      }
      if(!ok) ok=AggSlopeFromH1(12, up12);
      if(ok){ if(up12){ g_voteBull+=12; ft+="H12^ "; } else { g_voteBear+=12; ft+="H12v "; } }
   }

   // --- Filtro 6: H8 slope (peso 8) ---
   if(InpUseH8)
   {
      bool up8=false; bool ok=false;
      if(g_h8Native && hEMA50_H8!=INVALID_HANDLE)
      {
         double h8[3];
         if(CopyBuffer(hEMA50_H8,0,0,3,h8)==3){ up8=(h8[0]>h8[2]); ok=true; }
      }
      if(!ok) ok=AggSlopeFromH1(8, up8);
      if(ok){ if(up8){ g_voteBull+=8; ft+="H8^ "; } else { g_voteBear+=8; ft+="H8v "; } }
   }

   // --- Resolver ---
   g_filterTxt=ft;
   int tot=g_voteBull+g_voteBear;
   if(tot<=0){ g_dir=DIR_NONE; g_conf=0; return; }
   if(g_voteBull>g_voteBear)
   {
      g_conf=(int)MathRound(100.0*g_voteBull/(double)(g_voteBull+g_voteBear));
      g_dir=(g_conf>=InpConfidenceMin)?DIR_BULL:DIR_NONE;
   }
   else if(g_voteBear>g_voteBull)
   {
      g_conf=(int)MathRound(100.0*g_voteBear/(double)(g_voteBull+g_voteBear));
      g_dir=(g_conf>=InpConfidenceMin)?DIR_BEAR:DIR_NONE;
   }
   else { g_dir=DIR_NONE; g_conf=50; }
}

//====================================================================
//  SIZING UNIVERSAL
//====================================================================
double CalcLot(double stopDistPrice)
{
   if(InpRiskMode==RISK_FIXEDLOT) return NormalizeVolume(InpFixedLot);

   double tickSize =SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step     =SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickSize<=0 || tickValue<=0 || step<=0 || stopDistPrice<=0) return 0;

   double equity = InpCompound ? AccountInfoDouble(ACCOUNT_EQUITY)
                               : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskCash = equity*InpRiskPercent/100.0;
   if(InpMaxRiskCash>0 && riskCash>InpMaxRiskCash) riskCash=InpMaxRiskCash;

   double moneyPerLot = (stopDistPrice/tickSize)*tickValue;
   if(moneyPerLot<=0) return 0;

   double lots = riskCash/moneyPerLot;
   lots=NormalizeVolume(lots);
   if(lots<=0) return 0;

   // check margen
   double margin=0;
   double ask=SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,lots,ask,margin))
   {
      double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin>freeM*0.9 && margin>0)
      {
         double maxByM=lots*(freeM*0.9/margin);
         lots=NormalizeVolume(maxByM);
      }
   }
   return lots;
}

//====================================================================
//  VALIDAR STOPS
//====================================================================
void ValidStops(bool isBuy, double price, double &sl, double &tp)
{
   long stopsPts =SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezePts=SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax((double)stopsPts,(double)freezePts)*_Point
                  + SpreadPts()*_Point;
   if(stopsPts==0) minDist=MathMax(minDist, 10*_Point);
   double ts=SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) ts=_Point;
   if(isBuy)
   {
      if(sl>0 && price-sl<minDist) sl=price-minDist;
      if(tp>0 && tp-price<minDist) tp=price+minDist;
   }
   else
   {
      if(sl>0 && sl-price<minDist) sl=price+minDist;
      if(tp>0 && price-tp<minDist) tp=price-minDist;
   }
   if(sl>0) sl=MathRound(sl/ts)*ts;
   if(tp>0) tp=MathRound(tp/ts)*ts;
}

//====================================================================
//  ENTRADAS
//====================================================================
bool CrossSignal(int dir)  // dir: +1 bull, -1 bear ; usa barras cerradas [1],[2]
{
   double ef[2], es[2], sf[2], ss[2];
   ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
   ArraySetAsSeries(sf,true); ArraySetAsSeries(ss,true);
   if(CopyBuffer(hEMA9,0,1,2,ef)!=2)  return false;
   if(CopyBuffer(hEMA26,0,1,2,es)!=2) return false;
   if(CopyBuffer(hSMA9,0,1,2,sf)!=2)  return false;
   if(CopyBuffer(hSMA26,0,1,2,ss)!=2) return false;

   // index 0 = barra mas reciente cerrada [1]; index 1 = barra [2]
   bool emaBull=(ef[1]<=es[1] && ef[0]>es[0]);
   bool emaBear=(ef[1]>=es[1] && ef[0]<es[0]);
   bool smaBull=(sf[1]<=ss[1] && sf[0]>ss[0]);
   bool smaBear=(sf[1]>=ss[1] && sf[0]<ss[0]);

   bool bull=false, bear=false;
   switch(InpCrossMode)
   {
      case CROSS_EMA:    bull=emaBull; bear=emaBear; break;
      case CROSS_SMA:    bull=smaBull; bear=smaBear; break;
      case CROSS_BOTH:   bull=(emaBull&&smaBull); bear=(emaBear&&smaBear); break;
      default:           bull=(emaBull||smaBull); bear=(emaBear||smaBear); break;
   }

   // pendiente de la lenta
   if(InpUseSlopeFilter)
   {
      if(dir>0 && !(es[0]>es[1])) bull=false;
      if(dir<0 && !(es[0]<es[1])) bear=false;
   }
   // ADX entrada
   if(InpUseEntryADX)
   {
      double a[1];
      if(CopyBuffer(hADX_op,0,0,1,a)==1 && a[0]<InpEntryADXMin){ bull=false; bear=false; }
   }
   return (dir>0)?bull:bear;
}

void TryEntry()
{
   if(g_dir==DIR_NONE) return;
   if(!InpAllowPyramid && OpenPosCount()>0) return;
   if(SpreadPts()>InpMaxSpreadPts) return;
   if(AccountInfoDouble(ACCOUNT_EQUITY)<InpMinAccountUSD) return;

   datetime bt=iTime(_Symbol,g_opTF,0);
   if(bt==g_lastEntryBar) return; // ya se evaluo este bar

   int d=(g_dir==DIR_BULL)?1:-1;
   if(!CrossSignal(d)) return;
   g_lastEntryBar=bt;

   double atr[1];
   if(CopyBuffer(hATR,0,0,1,atr)!=1 || atr[0]<=0) return;
   double a=atr[0];

   double slMult=(g_profile==PROF_AGGRESSIVE)?InpAggSL:InpPatSL;
   double tpMult=(g_profile==PROF_AGGRESSIVE)?InpAggTP:InpPatTP;

   bool isBuy=(d>0);
   double price = isBuy?SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                       :SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = isBuy? price-a*slMult : price+a*slMult;
   double tp = isBuy? price+a*tpMult : price-a*tpMult;
   ValidStops(isBuy, price, sl, tp);

   double stopDist=MathAbs(price-sl);
   double lots=CalcLot(stopDist);
   if(lots<=0) return;

   // cap riesgo en cuentas muy pequenas
   double tickSize =SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize>0 && tickValue>0)
   {
      double riskUSD=(stopDist/tickSize)*tickValue*lots;
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if(riskUSD > eq*InpRiskPercent/100.0*2.0 && InpRiskMode==RISK_PERCENT) return;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFilling(PickFilling(_Symbol));

   bool ok = isBuy? trade.Buy(lots,_Symbol,price,sl,tp,"DDP")
                  : trade.Sell(lots,_Symbol,price,sl,tp,"DDP");
   if(ok) g_tradesToday++;
   else if(!g_isTester)
      Print("Entry fail: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//====================================================================
//  GESTION DE POSICIONES (exits adaptativos)
//====================================================================
bool g_partialDone[]; ulong g_partialTk[];
bool PartialDone(ulong tk)
{
   for(int i=0;i<ArraySize(g_partialTk);i++) if(g_partialTk[i]==tk) return g_partialDone[i];
   return false;
}
void MarkPartial(ulong tk)
{
   for(int i=0;i<ArraySize(g_partialTk);i++) if(g_partialTk[i]==tk){ g_partialDone[i]=true; return; }
   int n=ArraySize(g_partialTk); ArrayResize(g_partialTk,n+1); ArrayResize(g_partialDone,n+1);
   g_partialTk[n]=tk; g_partialDone[n]=true;
}

void ModifyStops(ulong tk, double sl, double tp)
{
   if(!pos.SelectByTicket(tk)) return;
   bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
   double price=pos.PriceCurrent();
   ValidStops(isBuy, price, sl, tp);
   if(MathAbs(sl-pos.StopLoss())<_Point && MathAbs(tp-pos.TakeProfit())<_Point) return;
   trade.PositionModify(tk, sl, tp);
}

void ManagePositions()
{
   double atr[1];
   if(CopyBuffer(hATR,0,0,1,atr)!=1 || atr[0]<=0) return;
   double a=atr[0];
   bool agg=(g_profile==PROF_AGGRESSIVE);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol()!=_Symbol || pos.Magic()!=InpMagic) continue;

      ulong tk=pos.Ticket();
      bool isBuy=(pos.PositionType()==POSITION_TYPE_BUY);
      double open=pos.PriceOpen();
      double sl=pos.StopLoss();
      double tp=pos.TakeProfit();
      double price=pos.PriceCurrent();
      double R = (sl>0)? MathAbs(open-sl) : a*(agg?InpAggSL:InpPatSL);
      if(R<=0) continue;
      double profitPx = isBuy?(price-open):(open-price);

      // parcial (solo agresivo)
      if(agg && !PartialDone(tk) && profitPx>=R*InpAggPartialR)
      {
         double half=NormalizeVolume(pos.Volume()*InpAggPartialPct/100.0);
         if(half>0 && half<pos.Volume())
         {
            trade.SetTypeFilling(PickFilling(_Symbol));
            if(trade.PositionClosePartial(tk, half)) MarkPartial(tk);
         }
         else MarkPartial(tk);
         double be=isBuy? open+SpreadPts()*_Point : open-SpreadPts()*_Point;
         ModifyStops(tk, be, tp);
         continue;
      }

      // trailing
      double trailMult=agg?InpAggTrail:InpPatTrail;
      double trigger  =agg?(1.5*R):(2.0*R);
      if(profitPx>=trigger)
      {
         double newSL=isBuy? price-trailMult*a : price+trailMult*a;
         if(isBuy && (sl==0 || newSL>sl)) ModifyStops(tk, newSL, tp);
         if(!isBuy && (sl==0 || newSL<sl)) ModifyStops(tk, newSL, tp);
      }
   }
}

//====================================================================
//  DIA / LIFECYCLE
//====================================================================
void HandleDayRollover()
{
   datetime today=iTime(_Symbol,PERIOD_D1,0);
   if(today==g_curDay) return;
   if(OpenPosCount()>0)
   {
      // hay trades cruzando el limite: NO resetear, no cerrar
      g_hasOpenSpan=true;
      return;
   }
   g_curDay=today;
   g_dailyPnL=0.0;
   g_winsToday=0; g_lossToday=0; g_tradesToday=0;
   g_hasOpenSpan=false;
}

//====================================================================
//  PANEL
//====================================================================
void Lbl(string name,int x,int y,color c,int fs,string txt)
{
   string n=PFX+name;
   if(ObjectFind(0,n)<0)
   {
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetString (0,n,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,n,OBJPROP_BACK,false);
   }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fs);
   if(ObjectGetString(0,n,OBJPROP_TEXT)!=txt) ObjectSetString(0,n,OBJPROP_TEXT,txt);
   if(ObjectGetInteger(0,n,OBJPROP_COLOR)!=(long)c) ObjectSetInteger(0,n,OBJPROP_COLOR,c);
}

void Box(int x,int y,int w,int h)
{
   string n=PFX+"BG";
   if(ObjectFind(0,n)<0)
   {
      ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrDimGray);
      ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'15,20,30');
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,n,OBJPROP_BACK,false);
   }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
}

string TFName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:return "M1"; case PERIOD_M5:return "M5";
      case PERIOD_M15:return "M15"; case PERIOD_M30:return "M30";
      case PERIOD_H1:return "H1"; case PERIOD_H4:return "H4";
      case PERIOD_D1:return "D1";
   }
   return EnumToString(tf);
}

void DrawPanel()
{
   int x=InpPanelX, y=InpPanelY;
   Box(x-6, y-6, 330, 322);
   int ly=y;
   Lbl("T", x, ly, clrGold, 11, "DailyDirection Pro  |  "+_Symbol); ly+=22;

   string dirS=(g_dir==DIR_BULL)?"ALCISTA":(g_dir==DIR_BEAR)?"BAJISTA":"NO-TRADE";
   color  dirC=(g_dir==DIR_BULL)?clrLime:(g_dir==DIR_BEAR)?clrTomato:clrSilver;
   Lbl("D", x, ly, dirC, 12, "Direccion dia: "+dirS); ly+=20;
   Lbl("C", x, ly, clrAqua, 9, StringFormat("Confianza: %d%% (min %d) | B:%d S:%d",
       g_conf, InpConfidenceMin, g_voteBull, g_voteBear)); ly+=18;
   Lbl("F", x, ly, clrLightGray, 8, "Filtros: "+g_filterTxt); ly+=20;

   string prof=(g_profile==PROF_AGGRESSIVE)?"AGRESIVO (scalp)":"PACIENTE (swing)";
   Lbl("P", x, ly, clrOrange, 9, "TF op: "+TFName(g_opTF)+" | Perfil: "+prof); ly+=20;

   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   Lbl("B", x, ly, clrWhite, 9, StringFormat("Balance: %.2f  Equity: %.2f", bal, eq)); ly+=18;

   double fpl=FloatingPnL();
   Lbl("FP", x, ly, fpl>=0?clrLime:clrTomato, 9,
       StringFormat("Pos abiertas: %d  Flotante: %.2f", OpenPosCount(), fpl)); ly+=18;

   color dpc=(g_dailyPnL>=0)?clrLime:clrTomato;
   Lbl("PL", x, ly, dpc, 9, StringFormat("PnL dia (cerrado): %.2f", g_dailyPnL)); ly+=18;

   double wr = (g_wlCount>0)? 100.0*RollingWins()/(double)g_wlCount : 0.0;
   Lbl("WL", x, ly, clrLightGray, 9, StringFormat("Hoy  W:%d L:%d  Trades:%d | WR20:%.0f%%",
       g_winsToday, g_lossToday, g_tradesToday, wr)); ly+=18;

   double atr[1]; double av=0;
   if(CopyBuffer(hATR,0,0,1,atr)==1) av=atr[0];
   Lbl("A", x, ly, clrLightGray, 8, StringFormat("ATR: %.5f | Spread: %d pts | Fill: %s",
       av, SpreadPts(), EnumToString(PickFilling(_Symbol)))); ly+=18;

   double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   Lbl("M", x, ly, clrLightGray, 8, StringFormat("Margin lvl: %.0f%% | Lev 1:%d",
       ml, (int)AccountInfoInteger(ACCOUNT_LEVERAGE))); ly+=18;

   string st;
   if(AccountInfoDouble(ACCOUNT_EQUITY)<InpMinAccountUSD) st="Capital < minimo";
   else if(SpreadPts()>InpMaxSpreadPts) st="Spread alto - esperando";
   else if(g_dir==DIR_NONE) st="Sin direccion clara - esperando";
   else if(OpenPosCount()>0) st="En operacion";
   else st="Buscando cruce 9/26 ("+dirS+")";
   Lbl("S", x, ly, clrYellow, 9, "Estado: "+st);

   if(!g_isTester) ChartRedraw();
}

int RollingWins(){ int w=0; for(int i=0;i<g_wlCount;i++) if(g_wlBuf[i]>0) w++; return w; }

void PanelClear()
{
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
   {
      string nm=ObjectName(0,i);
      if(StringFind(nm,PFX)==0) ObjectDelete(0,nm);
   }
}

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   g_isTester=(bool)MQLInfoInteger(MQL_TESTER);
   g_opTF=ResolveTF();
   g_profile=ResolveProfile(g_opTF);

   // Handles direccion D1
   hEMA50_D1 =iMA(_Symbol,PERIOD_D1,50,0,MODE_EMA,PRICE_CLOSE);
   hEMA200_D1=iMA(_Symbol,PERIOD_D1,200,0,MODE_EMA,PRICE_CLOSE);
   hADX_D1   =iADX(_Symbol,PERIOD_D1,14);
   hIchi_D1  =iIchimoku(_Symbol,PERIOD_D1,9,26,52);
   if(hEMA50_D1==INVALID_HANDLE||hEMA200_D1==INVALID_HANDLE||
      hADX_D1==INVALID_HANDLE||hIchi_D1==INVALID_HANDLE)
   { Print("Handle D1 invalido"); return INIT_FAILED; }

   // H12 / H8 nativos (si el broker los sirve)
   MqlRates tmp[];
   if(CopyRates(_Symbol,PERIOD_H12,0,3,tmp)>0)
   { hEMA50_H12=iMA(_Symbol,PERIOD_H12,50,0,MODE_EMA,PRICE_CLOSE); g_h12Native=(hEMA50_H12!=INVALID_HANDLE); }
   if(CopyRates(_Symbol,PERIOD_H8,0,3,tmp)>0)
   { hEMA50_H8=iMA(_Symbol,PERIOD_H8,50,0,MODE_EMA,PRICE_CLOSE); g_h8Native=(hEMA50_H8!=INVALID_HANDLE); }

   // Handles entrada TF operativo
   hSMA9 =iMA(_Symbol,g_opTF,9, 0,MODE_SMA,PRICE_CLOSE);
   hSMA26=iMA(_Symbol,g_opTF,26,0,MODE_SMA,PRICE_CLOSE);
   hEMA9 =iMA(_Symbol,g_opTF,9, 0,MODE_EMA,PRICE_CLOSE);
   hEMA26=iMA(_Symbol,g_opTF,26,0,MODE_EMA,PRICE_CLOSE);
   hATR  =iATR(_Symbol,g_opTF,InpATRPeriod);
   hADX_op=iADX(_Symbol,g_opTF,14);
   if(hSMA9==INVALID_HANDLE||hSMA26==INVALID_HANDLE||hEMA9==INVALID_HANDLE||
      hEMA26==INVALID_HANDLE||hATR==INVALID_HANDLE||hADX_op==INVALID_HANDLE)
   { Print("Handle entrada invalido"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFilling(PickFilling(_Symbol));

   g_curDay=iTime(_Symbol,PERIOD_D1,0);
   ArrayResize(g_partialTk,0); ArrayResize(g_partialDone,0);

   Print("DDP v1 init OK | TF:",TFName(g_opTF)," Perfil:",(g_profile==PROF_AGGRESSIVE?"AGG":"PAT"),
         " H12nat:",g_h12Native," H8nat:",g_h8Native);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEMA50_D1); IndicatorRelease(hEMA200_D1);
   IndicatorRelease(hADX_D1);   IndicatorRelease(hIchi_D1);
   if(hEMA50_H12!=INVALID_HANDLE) IndicatorRelease(hEMA50_H12);
   if(hEMA50_H8 !=INVALID_HANDLE) IndicatorRelease(hEMA50_H8);
   IndicatorRelease(hSMA9); IndicatorRelease(hSMA26);
   IndicatorRelease(hEMA9); IndicatorRelease(hEMA26);
   IndicatorRelease(hATR);  IndicatorRelease(hADX_op);
   PanelClear();
   Comment("");
}

//====================================================================
//  OnTick
//====================================================================
void OnTick()
{
   HandleDayRollover();

   // recalcular direccion en cada nueva barra D1 (y cada nueva H1 para refresco real)
   static datetime dirBar=0;
   if(IsNewBar(PERIOD_H1, dirBar) || g_dir==DIR_NONE || g_lastDirBar==0)
   {
      ComputeDirection();
      g_lastDirBar=iTime(_Symbol,PERIOD_D1,0);
   }

   // gestionar salidas siempre
   ManagePositions();

   // entrada solo en nueva barra del TF operativo
   static datetime entryBarChk=0;
   if(IsNewBar(g_opTF, entryBarChk))
      TryEntry();

   if(InpShowPanel) DrawPanel();
}

//====================================================================
//  OnTradeTransaction — PnL diario + lifecycle
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_IN){ g_hasOpenSpan=true; return; }

   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT)
   {
      double p=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)
              +HistoryDealGetDouble(trans.deal,DEAL_SWAP)
              +HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
      g_dailyPnL+=p;
      if(p>=0) g_winsToday++; else g_lossToday++;
      // rolling
      g_wlBuf[g_wlIdx]=(p>=0)?1:-1;
      g_wlIdx=(g_wlIdx+1)%20;
      if(g_wlCount<20) g_wlCount++;

      if(OpenPosCount()==0)
      {
         g_hasOpenSpan=false;
         datetime today=iTime(_Symbol,PERIOD_D1,0);
         if(today!=g_curDay)
         {
            g_curDay=today; g_dailyPnL=0.0;
            g_winsToday=0; g_lossToday=0; g_tradesToday=0;
         }
      }
   }
}
//+------------------------------------------------------------------+
