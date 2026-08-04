//+------------------------------------------------------------------+
//|                                   OWS_Pro_Dashboard_V15.mq5      |
//|                        Copyright 2025, OptiWealth Solutions       |
//|                                       https://www.optiwealth.ai  |
//+------------------------------------------------------------------+
//
//  LAYOUT V15
//  ┌────────────────────┐          ┌────────────┐
//  │  BLOC MTF          │          │  USDJPY    │  ← ticker seul
//  │  fond coloré       │          └────────────┘
//  │  police réduite    │
//  └────────────────────┘
//
//                              ┌────────────────────┐
//                              │  POSITIONS         │  ← bas droite
//                              │  spread / P&L etc. │
//                              └────────────────────┘
//
//  CHANGELOG V15
//  ─────────────────────────────────────────────────────────────────
//  [FIX]  Chevauchement lignes (lineHeight ≥ 2.2× fontSize)
//  [FIX]  Paramètre id inutilisé supprimé de CreateLbl
//  [FIX]  Labels fantômes nettoyés dynamiquement
//  [FIX]  to_copy sécurisé (débordement prev_calculated)
//  [NEW]  3 blocs séparés : MTF (haut gauche) / Ticker (haut droit)
//         / Positions+Spread (bas droit)
//  [NEW]  Fond semi-opaque + bordure sur chaque bloc (OBJ_RECTANGLE_LABEL)
//  [NEW]  Police MTF réduite indépendamment des autres blocs
//  [NEW]  Session de trading, RSI état textuel, alignement MAs
//  [NEW]  Bid/Ask supprimé du bas droit (ticker seul en haut droit)
//  [NEW]  CalcAdaptiveSizes → tailles recalculées à chaque resize
//  [NEW]  OnChartEvent → redessine à chaque redimensionnement
//+------------------------------------------------------------------+
#property copyright "OptiWealth Solutions"
#property version   "15.2"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "M20"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "M50"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "M200"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//==========================================================================
//  INPUTS
//==========================================================================
input group "=== Indicateurs Techniques ==="
input int  FastMA     = 20;
input int  MedMA      = 50;
input int  SlowMA     = 200;
input int  ADX_Per    = 14;
input int  ADX_Thresh = 25;

input group "=== Position Dashboard ==="
input int  X_Pos      = 10;          // Marge gauche du bloc MTF (px)
input int  Y_Pos      = 20;          // Marge haute  du bloc MTF (px)

input group "=== Couleurs des Panneaux ==="
input color MTFBgColor = C'10,18,38';   // Fond bloc MTF (bleu nuit)
input color MTFBdColor = C'40,80,160';  // Bordure bloc MTF
input color PosBgColor = C'10,28,16';   // Fond bloc Positions (vert nuit)
input color PosBdColor = C'30,100,50';  // Bordure bloc Positions

input group "=== Options ==="
input bool ShowSession = true;          // Afficher la session de trading

//==========================================================================
//  BUFFERS & HANDLES
//==========================================================================
double BufM20[], BufM50[], BufM200[];

int hM20, hM50, hM200, hRSI;
int hMTF_M20[4], hMTF_M50[4], hMTF_M200[4], hMTF_ADX[4];

ENUM_TIMEFRAMES TFs[4]    = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
string          TFNames[4] = {"M15", "H1 ", "H4 ", "D1 "};
const string    ObjPrefix  = "OWS_V15_";

//--- Tailles calculées dynamiquement
int g_MTFSize,  g_MTFLine;   // Bloc MTF  : police volontairement réduite
int g_TextSize, g_LineHeight; // Autres    : taille standard
int g_SmSize,   g_SmLine;    // Sous-texte: détails swap/comm/vol
int g_TickerSize;

//==========================================================================
//  INIT / DEINIT
//==========================================================================
int OnInit()
{
   SetIndexBuffer(0, BufM20,  INDICATOR_DATA);
   SetIndexBuffer(1, BufM50,  INDICATOR_DATA);
   SetIndexBuffer(2, BufM200, INDICATOR_DATA);

   hM20  = iMA(_Symbol, _Period, FastMA,  0, MODE_SMA, PRICE_CLOSE);
   hM50  = iMA(_Symbol, _Period, MedMA,   0, MODE_SMA, PRICE_CLOSE);
   hM200 = iMA(_Symbol, _Period, SlowMA,  0, MODE_SMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);

   for(int i = 0; i < 4; i++) {
      hMTF_M20[i]  = iMA(_Symbol, TFs[i], FastMA, 0, MODE_SMA, PRICE_CLOSE);
      hMTF_M50[i]  = iMA(_Symbol, TFs[i], MedMA,  0, MODE_SMA, PRICE_CLOSE);
      hMTF_M200[i] = iMA(_Symbol, TFs[i], SlowMA, 0, MODE_SMA, PRICE_CLOSE);
      hMTF_ADX[i]  = iADX(_Symbol, TFs[i], ADX_Per);
   }

   ObjectsDeleteAll(0, ObjPrefix);
   CalcAdaptiveSizes();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, ObjPrefix); }

//==========================================================================
//  TAILLES ADAPTATIVES
//  Référence : 900 px de hauteur fenêtre
//  Règle anti-chevauchement garantie : lineHeight ≥ ceil(fontSize × 2.2)
//==========================================================================
void CalcAdaptiveSizes()
{
   long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(h <= 0) h = 700;
   double r = MathMax(0.5, MathMin(2.0, (double)h / 900.0));

   // Bloc MTF : volontairement plus petit que le reste
   g_MTFSize  = (int)MathMax(6,  MathMin(11, (int)MathRound(7.0 * r)));
   g_MTFLine  = (int)MathMax(12, MathMin(28, (int)MathMax((int)MathCeil(g_MTFSize * 2.2),
                                                           (int)MathRound(14.0 * r))));

   // Taille principale (titres, P&L net…)
   g_TextSize   = (int)MathMax(8,  MathMin(14, (int)MathRound(9.0  * r)));
   g_LineHeight = (int)MathMax(13, MathMin(34, (int)MathMax((int)MathCeil(g_TextSize * 2.2),
                                                             (int)MathRound(18.0 * r))));

   // Sous-texte (détails positionnement, swap…)
   g_SmSize = (int)MathMax(6,  MathMin(11, (int)MathRound(7.0  * r)));
   g_SmLine = (int)MathMax(10, MathMin(26, (int)MathMax((int)MathCeil(g_SmSize * 2.2),
                                                         (int)MathRound(14.0 * r))));

   g_TickerSize = (int)MathMax(14, MathMin(46, (int)MathRound(20.0 * r)));
}

//==========================================================================
//  CHART EVENT – redessine si la fenêtre est redimensionnée
//==========================================================================
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id == CHARTEVENT_CHART_CHANGE) {
      CalcAdaptiveSizes();
      DrawDashboard();
      ChartRedraw(0);
   }
}

//==========================================================================
//  CALCUL PRINCIPAL
//==========================================================================
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < SlowMA) return(0);

   int to_copy = (prev_calculated <= 0 || prev_calculated > rates_total)
                 ? rates_total : (rates_total - prev_calculated + 1);

   if(CopyBuffer(hM20,  0, 0, to_copy, BufM20)  <= 0) return(0);
   if(CopyBuffer(hM50,  0, 0, to_copy, BufM50)  <= 0) return(0);
   if(CopyBuffer(hM200, 0, 0, to_copy, BufM200) <= 0) return(0);

   DrawDashboard();
   ChartRedraw(0);
   return(rates_total);
}

//==========================================================================
//  DRAW DASHBOARD
//==========================================================================
void DrawDashboard()
{
   DrawMTFBlock();
   DrawTicker();
   DrawBottomRightPanel();
}

//==========================================================================
//  BLOC 1 — ANALYSE MTF (haut gauche, fond coloré, police réduite)
//==========================================================================
void DrawMTFBlock()
{
   // ── Compter les lignes pour calculer la hauteur du fond ──────
   int nLines = 1       // titre
               + 4       // 4 TF
               + 1       // RSI
               + 1;      // alignement MAs
   if(ShowSession) nLines++;

   int padX = 8, padY = 7;
   int bkgW  = (int)MathMax(190, g_MTFSize * 24 + 2 * padX);
   int bkgH  = 2 * padY + nLines * g_MTFLine;

   // ── Fond (OBJ_RECTANGLE_LABEL, zorder 0 → derrière les textes) ──
   DrawBgRect("MTF_BG",
              X_Pos - padX, Y_Pos - padY, bkgW, bkgH,
              MTFBgColor, MTFBdColor,
              CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);

   // ── Labels ────────────────────────────────────────────────────
   int y = Y_Pos;

   CreateLbl("MTF_0", X_Pos, y, "─ ANALYSE MTF ─", clrSilver, g_MTFSize, false);
   y += g_MTFLine;

   for(int i = 0; i < 4; i++) {
      string txt; color c;
      GetTFState(i, txt, c);
      CreateLbl("MTF_TF" + (string)i, X_Pos, y,
                TFNames[i] + ": " + txt, c, g_MTFSize, true);
      y += g_MTFLine;
   }

   // RSI
   double rsiV[1];
   if(CopyBuffer(hRSI, 0, 0, 1, rsiV) > 0) {
      color rc = clrLightGray; string rs = "Neutre";
      if     (rsiV[0] >= 70) { rc = clrOrangeRed;      rs = "Suracheté ⚠"; }
      else if(rsiV[0] <= 30) { rc = clrDodgerBlue;     rs = "Survendu ⚠";  }
      else if(rsiV[0] >  55) { rc = clrMediumSeaGreen; rs = "Haussier";    }
      else if(rsiV[0] <  45) { rc = clrSalmon;         rs = "Baissier";    }
      CreateLbl("MTF_RSI", X_Pos, y,
                "RSI " + DoubleToString(rsiV[0], 1) + " – " + rs,
                rc, g_MTFSize, false);
      y += g_MTFLine;
   }

   // Alignement MAs
   {
      double m20c[1], m50c[1], m200c[1], pC[1];
      if(CopyBuffer(hM20,  0, 0, 1, m20c)  > 0 &&
         CopyBuffer(hM50,  0, 0, 1, m50c)  > 0 &&
         CopyBuffer(hM200, 0, 0, 1, m200c) > 0 &&
         CopyClose(_Symbol, _Period, 0, 1, pC) > 0)
      {
         bool bull = (pC[0]>m20c[0] && m20c[0]>m50c[0] && m50c[0]>m200c[0]);
         bool bear = (pC[0]<m20c[0] && m20c[0]<m50c[0] && m50c[0]<m200c[0]);
         string mt; color mc;
         if(bull)      { mt = "MAs ▲ Alignées"; mc = clrGreen;    }
         else if(bear) { mt = "MAs ▼ Alignées"; mc = clrRed;      }
         else          { mt = "MAs Mixtes";      mc = clrDarkGray; }
         CreateLbl("MTF_MA", X_Pos, y, mt, mc, g_MTFSize, false);
         y += g_MTFLine;
      }
   }

   // Session
   if(ShowSession) {
      string sess; color sc;
      GetCurrentSession(sess, sc);
      CreateLbl("MTF_SESS", X_Pos, y, sess, sc, g_MTFSize, false);
   }
}

//==========================================================================
//  BLOC 2 — TICKER (haut droit, symbole seul)
//==========================================================================
void DrawTicker()
{
   string n = ObjPrefix + "TKR";
   if(ObjectFind(0, n) < 0) {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 6);
      ObjectSetString( 0, n, OBJPROP_FONT,      "Arial Black");
      ObjectSetInteger(0, n, OBJPROP_ZORDER,    10);
   }
   ObjectSetInteger(0, n, OBJPROP_COLOR,    clrWhite);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, g_TickerSize);
   ObjectSetString( 0, n, OBJPROP_TEXT,     _Symbol);

   // Supprimer les anciens labels droite de V14 (migration propre)
   ObjectDelete(0, ObjPrefix + "BIG_TICKER");
   ObjectDelete(0, ObjPrefix + "PROFIT_LABEL");
   ObjectDelete(0, ObjPrefix + "RT_TKR");
   ObjectDelete(0, ObjPrefix + "RT_BA");
   ObjectDelete(0, ObjPrefix + "RT_PNL");
}

//==========================================================================
//  BLOC 3 — POSITIONS + SPREAD (bas droit, fond coloré)
//  Construction bottom-up : la première ligne dessinée est la plus basse
//==========================================================================
void DrawBottomRightPanel()
{
   // ── Collecte des données positions ───────────────────────────
   double totPnl=0, totSwap=0, totComm=0, totVol=0;
   double buyVol=0, sellVol=0, sumBuyPx=0, sumSellPx=0;
   int    buyCnt=0, sellCnt=0;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionGetSymbol(i) != _Symbol) continue;
      int    pt  = (int)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double px  = PositionGetDouble(POSITION_PRICE_OPEN);
      totPnl  += PositionGetDouble(POSITION_PROFIT);
      totSwap += PositionGetDouble(POSITION_SWAP);
      totComm += PositionGetDouble(POSITION_COMMISSION);
      totVol  += vol;
      if(pt == POSITION_TYPE_BUY) { buyCnt++;  buyVol  += vol; sumBuyPx  += px*vol; }
      else                         { sellCnt++; sellVol += vol; sumSellPx += px*vol; }
   }

   int    total = buyCnt + sellCnt;
   string ccy   = AccountInfoString(ACCOUNT_CURRENCY);
   double net   = totPnl + totSwap + totComm;

   // ── Calcul précis de la hauteur du fond ───────────────────────
   //   Chaque ligne a sa propre hauteur (SmLine ou LineHeight)
   int padX = 8, padY = 7;
   int rX   = 12, bMrg = 12;

   int bkgH = 2 * padY;
   bkgH += g_SmLine;                              // spread (toujours)
   if(total > 0) {
      bkgH += g_SmLine;                           // brut/swap/comm
      bkgH += g_LineHeight;                       // P&L net  (plus grand)
      bkgH += g_SmLine;                           // volume total
      if(buyCnt  > 0) bkgH += g_SmLine;           // ligne achat
      if(sellCnt > 0) bkgH += g_SmLine;           // ligne vente
      bkgH += g_SmLine;                           // séparateur
      bkgH += g_LineHeight;                       // en-tête POSITIONS
   } else {
      bkgH += g_LineHeight;                       // "Aucune position"
   }

   int bkgW = (int)MathMax(220, g_TextSize * 27 + 2 * padX);

   // ── Fond (ancre bas-droit, s'étend vers le haut et la gauche) ─
   DrawBgRect("BR_BG",
              rX - padX, bMrg - padY, bkgW, bkgH,
              PosBgColor, PosBdColor,
              CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);

   // ── Labels bottom-up ──────────────────────────────────────────
   int bY = bMrg;

   // ① Spread  (ligne la plus basse)
   long  spd = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   color spc = (spd < 15) ? clrLightGreen : (spd < 50) ? clrYellow : clrOrangeRed;
   CreateBRLbl("BR_SPR", rX, bY,
      "Spread : " + (string)spd + " pts", spc, g_SmSize, false);
   bY += g_SmLine;

   if(total > 0)
   {
      // ② Brut / Swap / Comm
      CreateBRLbl("BR_GRS", rX, bY,
         "Brut " + Fmt(totPnl) + "  Swap " + Fmt(totSwap) +
         "  Comm " + Fmt(totComm) + " " + ccy,
         clrDimGray, g_SmSize, false);
      bY += g_SmLine;

      // ③ P&L net  (taille plus grande, gras)
      CreateBRLbl("BR_NET", rX, bY,
         "P&L net : " + Fmt(net) + " " + ccy,
         net >= 0 ? clrLimeGreen : clrOrangeRed,
         g_TextSize + 1, true);
      bY += g_LineHeight;

      // ④ Volume total
      CreateBRLbl("BR_VOL", rX, bY,
         "Volume : " + DoubleToString(totVol, 2) + " lot",
         clrGray, g_SmSize, false);
      bY += g_SmLine;

      // ⑤ Vente
      if(sellCnt > 0) {
         double avgS = (sellVol > 0) ? sumSellPx / sellVol : 0;
         CreateBRLbl("BR_SEL", rX, bY,
            "▼ Vente : " + (string)sellCnt + " · " +
            DoubleToString(sellVol, 2) + " lot · moy " +
            DoubleToString(avgS, _Digits),
            clrSalmon, g_SmSize, false);
         bY += g_SmLine;
      } else { ObjectDelete(0, ObjPrefix + "BR_SEL"); }

      // ⑥ Achat
      if(buyCnt > 0) {
         double avgB = (buyVol > 0) ? sumBuyPx / buyVol : 0;
         CreateBRLbl("BR_BUY", rX, bY,
            "▲ Achat : " + (string)buyCnt + " · " +
            DoubleToString(buyVol, 2) + " lot · moy " +
            DoubleToString(avgB, _Digits),
            clrLightGreen, g_SmSize, false);
         bY += g_SmLine;
      } else { ObjectDelete(0, ObjPrefix + "BR_BUY"); }

      // ⑦ Séparateur
      CreateBRLbl("BR_SEP", rX, bY,
         "──────────────────", clrDimGray, g_SmSize - 1, false);
      bY += g_SmLine;

      // ⑧ En-tête POSITIONS  (ligne la plus haute du bloc)
      CreateBRLbl("BR_HDR", rX, bY,
         "POSITIONS : " + (string)total + " ouverte" + (total > 1 ? "s" : ""),
         clrWhite, g_TextSize, true);
   }
   else
   {
      // Nettoyage labels trade quand aucune position
      string toClean[] = {"BR_GRS","BR_NET","BR_VOL","BR_SEL","BR_BUY","BR_SEP"};
      for(int k = 0; k < 6; k++) ObjectDelete(0, ObjPrefix + toClean[k]);

      CreateBRLbl("BR_HDR", rX, bY,
         "Aucune position", clrGray, g_TextSize, false);
   }
}

//==========================================================================
//  HELPER — Fond rectangulaire (OBJ_RECTANGLE_LABEL)
//  xDist / yDist : distance depuis le coin choisi
//  Pour CORNER_RIGHT_LOWER + ANCHOR_RIGHT_LOWER : le rectangle
//  s'étend vers la gauche (xSize) et vers le haut (ySize)
//==========================================================================
void DrawBgRect(const string suffix,
                int xDist, int yDist, int xSize, int ySize,
                color bgClr, color bdClr,
                ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor)
{
   string n = ObjPrefix + suffix;
   if(ObjectFind(0, n) < 0) {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, n, OBJPROP_ZORDER,       0);   // derrière les textes (zorder 10)
   }
   ObjectSetInteger(0, n, OBJPROP_CORNER,      corner);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,      anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   xDist);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   yDist);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        xSize);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        ySize);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        bdClr);
}

//==========================================================================
//  SESSION DE TRADING (heure serveur ≈ UTC – à ajuster selon le broker)
//==========================================================================
void GetCurrentSession(string &outSess, color &outColor)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hh = dt.hour;
   if     (hh <  8) { outSess = "Tokyo / Sydney";    outColor = clrMediumOrchid; }
   else if(hh < 13) { outSess = "Londres";           outColor = clrDeepSkyBlue;  }
   else if(hh < 17) { outSess = "Overlap LDN/NY ★"; outColor = clrGold;          }
   else if(hh < 22) { outSess = "New York";          outColor = clrYellow;        }
   else             { outSess = "Pré-Asie";          outColor = clrDimGray;       }
}

//==========================================================================
//  ÉTAT MTF
//==========================================================================
void GetTFState(int index, string &outText, color &outColor)
{
   double m20[1], m50[1], m200[1], adx[1], pC[1];
   if(CopyBuffer(hMTF_M20[index],  0, 0, 1, m20)  <= 0 ||
      CopyBuffer(hMTF_M50[index],  0, 0, 1, m50)  <= 0 ||
      CopyBuffer(hMTF_M200[index], 0, 0, 1, m200) <= 0 ||
      CopyBuffer(hMTF_ADX[index],  0, 0, 1, adx)  <= 0 ||
      CopyClose(_Symbol, TFs[index], 0, 1, pC) <= 0)
   { outText = "..."; outColor = clrGray; return; }

   bool bull   = (pC[0]>m20[0] && m20[0]>m50[0] && m50[0]>m200[0]);
   bool bear   = (pC[0]<m20[0] && m20[0]<m50[0] && m50[0]<m200[0]);
   bool strong = (adx[0] > ADX_Thresh);
   string adxS = "(" + DoubleToString(adx[0], 0) + ")";

   if     (bull &&  strong) { outText = "▲ ACHAT Fort "   + adxS; outColor = clrGreen;     }
   else if(bear &&  strong) { outText = "▼ VENTE Forte "  + adxS; outColor = clrRed;       }
   else if(bull && !strong) { outText = "∆ ACHAT Faible " + adxS; outColor = clrTeal;      }
   else if(bear && !strong) { outText = "∇ VENTE Faible " + adxS; outColor = clrFireBrick; }
   else                     { outText = "► Neutre";                outColor = clrWhite;     }
}

//==========================================================================
//  HELPERS — Labels
//==========================================================================

// Label standard (coin haut gauche)
void CreateLbl(const string suffix, int x, int y,
               const string text, color clr, int sz, bool bold)
{
   string n = ObjPrefix + suffix;
   if(ObjectFind(0, n) < 0) {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_ZORDER,    10);
   }
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString( 0, n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   sz);
   ObjectSetString( 0, n, OBJPROP_FONT, bold ? "Tahoma Bold" : "Tahoma");
}

// Label bas-droit (coin bas droit, aligné à droite, construit bottom-up)
void CreateBRLbl(const string suffix, int xDist, int yDist,
                 const string text, color clr, int sz, bool bold)
{
   string n = ObjPrefix + suffix;
   if(ObjectFind(0, n) < 0) {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR,    ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, xDist);
      ObjectSetInteger(0, n, OBJPROP_ZORDER,    10);
   }
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, yDist);
   ObjectSetString( 0, n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   sz);
   ObjectSetString( 0, n, OBJPROP_FONT, bold ? "Tahoma Bold" : "Tahoma");
}

// Affichage signe +/– systématique
string Fmt(double v)
{
   return (v >= 0 ? "+" : "") + DoubleToString(v, 2);
}
