//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh |
//| Painel visual no gráfico: estado do EA, P/L diário, drawdown.   |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeEA/Defines.mqh>

#define BTCEA_DASH_PREFIX "BTCEA_DASH_"

class CDashboard
  {
private:
   long   m_chartId;
   string m_prefix;
   int    m_x;
   int    m_y;

   void CreateLabel(const string name,const int x,const int y,const string text,
                     const color clr,const int fontSize = 9)
     {
      string objName = m_prefix + name;
      if(ObjectFind(m_chartId, objName) < 0)
        {
         ObjectCreate(m_chartId, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
         ObjectSetString(m_chartId, objName, OBJPROP_FONT, "Consolas");
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
         ObjectSetInteger(m_chartId, objName, OBJPROP_BGCOLOR, C'20,20,20');
         ObjectSetInteger(m_chartId, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(m_chartId, objName, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
        }
     }

public:
   CDashboard(void)
     {
      m_chartId = 0;
      m_prefix  = BTCEA_DASH_PREFIX;
      m_x       = 15;
      m_y       = 25;
     }

   void Init(const long chartId,const string uniqueSuffix)
     {
      m_chartId = chartId;
      m_prefix  = BTCEA_DASH_PREFIX + uniqueSuffix + "_";
      CreateBackground(230, 165);
     }

   void Remove(void)
     {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
     }

   void Update(const string eaName,const ENUM_EA_STATE state,const double dailyPnlPercent,
               const double drawdownPercent,const double equity,const double balance,
               const int mainBuy,const int mainSell,const int hedgeCount,
               const string extraLine = "")
     {
      color stateColor = clrLimeGreen;
      string stateText  = "OPERANDO";
      if(state == EA_STATE_DAILY_LOSS)   { stateColor = clrRed;     stateText = "BLOQUEADO: DAILY LOSS";  }
      if(state == EA_STATE_DAILY_PROFIT) { stateColor = clrGold;    stateText = "BLOQUEADO: DAILY GAIN";  }
      if(state == EA_STATE_MAX_DRAWDOWN) { stateColor = clrRed;     stateText = "BLOQUEADO: MAX DRAWDOWN";}
      if(state == EA_STATE_OUT_OF_SESSION){ stateColor = clrSilver; stateText = "FORA DE SESSAO";         }

      color pnlColor = (dailyPnlPercent >= 0) ? clrLimeGreen : clrOrangeRed;

      CreateLabel("Title", m_x, m_y, eaName, clrWhite, 10);
      CreateLabel("State", m_x, m_y + 20, "Estado: " + stateText, stateColor);
      CreateLabel("Daily", m_x, m_y + 40, StringFormat("P/L Diario: %.2f%%", dailyPnlPercent), pnlColor);
      CreateLabel("DD", m_x, m_y + 60, StringFormat("Drawdown (pico): %.2f%%", drawdownPercent), clrKhaki);
      CreateLabel("Equity", m_x, m_y + 80, StringFormat("Equity: %.2f  Balance: %.2f", equity, balance), clrWhite);
      CreateLabel("Pos", m_x, m_y + 100, StringFormat("Posicoes -> Compra: %d  Venda: %d  Hedge: %d", mainBuy, mainSell, hedgeCount), clrWhite);

      if(extraLine != "")
         CreateLabel("Extra", m_x, m_y + 120, extraLine, clrAqua);

      ChartRedraw(m_chartId);
     }
  };
