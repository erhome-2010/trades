//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh |
//| Painel visual no grafico: estado do EA, P/L diario, drawdown,   |
//| e o detalhe das duas pernas do grid (compra/venda).             |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeGridEA/Defines.mqh>

#define HGEA_DASH_PREFIX "BTCHGEA_DASH_"

class CHgDashboard
  {
private:
   long   m_chartId;
   string m_prefix;
   int    m_x;
   int    m_y;

   void CreateLabel(const string name,const int x,const int y,const string text,
                     const color clr,const int fontSize = 9,const string font = "Consolas")
     {
      string objName = m_prefix + name;
      if(ObjectFind(m_chartId, objName) < 0)
        {
         ObjectCreate(m_chartId, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
         ObjectSetString(m_chartId, objName, OBJPROP_FONT, font);
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
        }
      ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clr);
     }

   void CreateBackground(const int width,const int height)
     {
      string objName = m_prefix + "BG";
      if(ObjectFind(m_chartId, objName) < 0)
        {
         ObjectCreate(m_chartId, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, m_x - 10);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, m_y - 10);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XSIZE, width);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YSIZE, height);
         ObjectSetInteger(m_chartId, objName, OBJPROP_BGCOLOR, C'18,18,17');
         ObjectSetInteger(m_chartId, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(m_chartId, objName, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
        }
     }

public:
   CHgDashboard(void)
     {
      m_chartId = 0;
      m_prefix  = HGEA_DASH_PREFIX;
      m_x       = 15;
      m_y       = 25;
     }

   void Init(const long chartId,const string uniqueSuffix)
     {
      m_chartId = chartId;
      m_prefix  = HGEA_DASH_PREFIX + uniqueSuffix + "_";
      CreateBackground(280, 245);
     }

   void Remove(void)
     {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
     }

   void Update(const ENUM_HG_STATE state,const double dailyPnlPercent,const double dailyPnlUsd,
               const double drawdownPercent,const double equity,const double balance,
               const int buyOpen,const int buyTier,const int buyMaxTier,const double buyNextVol,const double buyPnl,
               const int sellOpen,const int sellTier,const int sellMaxTier,const double sellNextVol,const double sellPnl,
               const double worstCaseUsdPerSide)
     {
      color stateColor = clrLimeGreen;
      string stateText  = "OPERANDO";
      if(state == HG_STATE_DAILY_LOSS)   { stateColor = clrRed;  stateText = "BLOQUEADO: DAILY LOSS";  }
      if(state == HG_STATE_DAILY_PROFIT) { stateColor = clrGold; stateText = "BLOQUEADO: DAILY GAIN";  }
      if(state == HG_STATE_MAX_DRAWDOWN) { stateColor = clrRed;  stateText = "BLOQUEADO: MAX DRAWDOWN"; }

      color dailyColor = (dailyPnlUsd >= 0) ? clrLimeGreen : clrOrangeRed;
      color buyColor    = (buyPnl >= 0)   ? clrLimeGreen : clrOrangeRed;
      color sellColor   = (sellPnl >= 0)  ? clrLimeGreen : clrOrangeRed;

      int y = m_y;
      CreateLabel("Title", m_x, y, "BTC HedgeGrid EA", clrWhite, 11); y += 22;
      CreateLabel("State", m_x, y, "Estado: " + stateText, stateColor); y += 20;
      CreateLabel("Daily", m_x, y, StringFormat("Dia: %.2f%%  (%.2f USD)", dailyPnlPercent, dailyPnlUsd), dailyColor); y += 18;
      CreateLabel("DD", m_x, y, StringFormat("Drawdown do pico: %.2f%%", drawdownPercent), clrKhaki); y += 18;
      CreateLabel("Equity", m_x, y, StringFormat("Equity: %.2f   Balance: %.2f", equity, balance), clrWhite); y += 22;

      CreateLabel("BuyHead", m_x, y, "COMPRA", clrDodgerBlue, 10); y += 18;
      CreateLabel("BuyLine1", m_x, y, StringFormat("  Posicoes: %d   Tier: %d/%d", buyOpen, buyTier, buyMaxTier), clrWhite); y += 16;
      CreateLabel("BuyLine2", m_x, y, StringFormat("  Proximo vol: %.2f   P/L: %.2f", buyNextVol, buyPnl), buyColor); y += 22;

      CreateLabel("SellHead", m_x, y, "VENDA", clrTomato, 10); y += 18;
      CreateLabel("SellLine1", m_x, y, StringFormat("  Posicoes: %d   Tier: %d/%d", sellOpen, sellTier, sellMaxTier), clrWhite); y += 16;
      CreateLabel("SellLine2", m_x, y, StringFormat("  Proximo vol: %.2f   P/L: %.2f", sellNextVol, sellPnl), sellColor); y += 22;

      CreateLabel("Worst", m_x, y, StringFormat("Pior caso p/ lado (limite): ~%.2f USD", worstCaseUsdPerSide), clrSilver, 8);

      ChartRedraw(m_chartId);
     }
  };
