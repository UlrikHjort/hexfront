-- ***************************************************************************
--                    Hexfront - Game_Window
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada.Command_Line;
with Ada.Directories;
with Cairo;
with Glib;                    use Glib;
with Glib.Main;               use type Glib.Main.G_Source_Id;
with Gdk.Event;               use Gdk.Event;
with Gdk.Types;               use Gdk.Types;
with Gdk.Types.Keysyms;       use Gdk.Types.Keysyms;
with Gtk.Main;
with Gtk.Window;              use Gtk.Window;
with Gtk.Widget;              use Gtk.Widget;
with Gtk.Box;                 use Gtk.Box;
with Gtk.Paned;               use Gtk.Paned;
with Gtk.Drawing_Area;        use Gtk.Drawing_Area;
with Gtk.Scrolled_Window;     use Gtk.Scrolled_Window;
with Gtk.Adjustment;
with Gtk.Label;               use Gtk.Label;
with Gtk.Button;              use Gtk.Button;
with Gtk.Frame;               use Gtk.Frame;
with Gtk.Text_View;           use Gtk.Text_View;
with Gtk.Text_Buffer;         use Gtk.Text_Buffer;
with Gtk.Text_Iter;           use Gtk.Text_Iter;
with Gtk.Text_Mark;           use Gtk.Text_Mark;
with Gtk.Menu_Bar;            use Gtk.Menu_Bar;
with Gtk.Menu;                use Gtk.Menu;
with Gtk.Menu_Item;           use Gtk.Menu_Item;
with Gtk.Check_Menu_Item;     use Gtk.Check_Menu_Item;
with Gtk.Separator_Menu_Item; use Gtk.Separator_Menu_Item;
with Gtk.Dialog;              use Gtk.Dialog;
with Gtk.Message_Dialog;      use Gtk.Message_Dialog;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter;         use Gtk.File_Filter;
with Gtk.Combo_Box;
with Gtk.Combo_Box_Text;      use Gtk.Combo_Box_Text;
with Gtk.Enums;               use Gtk.Enums;
with Engine;                  use Engine;
with Engine.Hexes;            use Engine.Hexes;
with Engine.Terrain;          use Engine.Terrain;
with Engine.Units;            use Engine.Units;
with Engine.Game;             use Engine.Game;
with Engine.Loader;
with Engine.AI;
with Engine.Save;
with Engine.Campaign;
with Map_Render;              use Map_Render;
with Anim;
with Sound;
with Editor;
with Campaign_HQ;
with Oob_Window;

package body Game_Window is

   type Natural_Array is array (Positive range <>) of Natural;

   Win          : Gtk_Window;
   Area         : Gtk_Drawing_Area;
   Map_Scroll   : Gtk_Scrolled_Window;
   Status_Label : Gtk_Label;
   Unit_Label   : Gtk_Label;
   Info_Label   : Gtk_Label;
   Log_Buffer   : Gtk_Text_Buffer;
   Log_View     : Gtk_Text_View;
   Log_End      : Gtk_Text_Mark;
   Fog_Item     : Gtk_Check_Menu_Item;
   Fair_Item    : Gtk_Check_Menu_Item;
   Btn_Resupply, Btn_Reinforce, Btn_Buy, Btn_Next, Btn_End : Gtk_Button;
   Btn_Undo     : Gtk_Button;
   Mini         : Gtk_Drawing_Area;
   Supply_Item  : Gtk_Check_Menu_Item;

   View         : View_State;
   AI_Running   : Boolean := False;
   AI_Source    : Glib.Main.G_Source_Id := 0;
   Winner_Shown : Boolean := False;
   In_Dialog    : Boolean := False;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Img;

   function Fmt1 (F : Float) return String is
      T : constant Integer := Integer (F * 10.0);
   begin
      return Img (T / 10) & "." & Img (abs (T) mod 10);
   end Fmt1;

   --  Pango markup must not see raw '&', '<', '>'.
   function Esc (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '&' => Append (R, "&amp;");
            when '<' => Append (R, "&lt;");
            when '>' => Append (R, "&gt;");
            when others => Append (R, C);
         end case;
      end loop;
      return To_String (R);
   end Esc;

   function Human_Turn return Boolean is
     (G.Loaded and then G.Winner = 0 and then not AI_Running
      and then not Editor.Active
      and then G.Sides (G.Current).Control = Human);

   --  Whose eyes do we look through?
   function Viewer return Side_Id is
   begin
      if not G.Loaded or else not G.Fog or else G.Winner /= 0
        or else Editor.Active
      then
         return 0;
      elsif G.Sides (G.Current).Control = Human then
         return G.Current;
      elsif G.Sides (Other (G.Current)).Control = Human then
         return Other (G.Current);
      else
         return 0;   --  computer vs computer: show everything
      end if;
   end Viewer;

   function Shown (U : Natural) return Boolean is
     (U /= No_Unit and then Get (U).Alive
      and then (View.Viewer = 0 or else Visible (U, View.Viewer)));

   procedure Show_Message (Kind : Gtk_Message_Type; Text : String;
                           Title : String := "") is
      D : Gtk_Message_Dialog;
      R : Gtk_Response_Type;
      pragma Unreferenced (R);
   begin
      In_Dialog := True;
      Gtk_New (D, Win, Modal, Kind, Buttons_Ok, Text);
      if Title /= "" then
         D.Set_Title (Title);
      end if;
      R := D.Run;
      D.Destroy;
      In_Dialog := False;
   end Show_Message;

   ---------------------
   -- Panel refreshes --
   ---------------------

   procedure Flush_Log is
      Iter : Gtk_Text_Iter;
   begin
      if Messages.Is_Empty then
         return;
      end if;
      for M of Messages loop
         Log_Buffer.Get_End_Iter (Iter);
         Log_Buffer.Insert (Iter, M & ASCII.LF);
      end loop;
      Messages.Clear;
      Log_Buffer.Get_End_Iter (Iter);
      Log_Buffer.Move_Mark (Log_End, Iter);
      Log_View.Scroll_To_Mark (Log_End, 0.0, False, 0.0, 0.0);
   end Flush_Log;

   function Unit_Text (U : Unit_Index) return String is
      Un  : constant Unit      := Get (U);
      T   : constant Unit_Type := Type_Of (U);
      Own : constant Boolean   :=
        View.Viewer = 0 or else Un.Side = View.Viewer;
      S   : Unbounded_String;
   begin
      Append (S, "<b>" & Esc (To_String (T.Name)) & "</b>  ("
              & Esc (To_String (G.Sides (Un.Side).Name)) & ")" & ASCII.LF);
      Append (S, Class_Name (T.Class) & ", "
              & (case T.Target is
                    when Hard => "hard",
                    when Soft => "soft",
                    when Air  => "air")
              & " target" & ASCII.LF);
      Append (S, "Strength " & Img (Un.Strength) & "/10   Exp "
              & Img (Un.Experience) & " (" & Img (Exp_Level (Un))
              & " stars)" & ASCII.LF);
      Append (S, "Attack soft " & Img (T.Soft_Attack) & " / hard "
              & Img (T.Hard_Attack) & " / air " & Img (T.Air_Attack)
              & ASCII.LF & "Defence " & Img (T.Defense)
              & "   Range " & Img (T.Max_Range)
              & "   Spot " & Img (T.Spot) & ASCII.LF);
      if Own then
         Append (S, "Move " & Img (Un.Moves_Left) & "/" & Img (T.Movement)
                 & "   Ammo " & Img (Un.Ammo) & "/" & Img (T.Max_Ammo));
         if T.Max_Fuel > 0 then
            Append (S, "   Fuel " & Img (Un.Fuel) & "/" & Img (T.Max_Fuel));
         end if;
         Append (S, "" & ASCII.LF);
      else
         Append (S, "Move " & Img (T.Movement) & ASCII.LF);
      end if;
      if not Is_Air (T) then
         Append (S, "Entrenchment " & Img (Un.Entrench));
      end if;
      if Un.Suppressed > 0 then
         Append (S, "   Suppressed " & Img (Un.Suppressed));
      end if;
      if Is_Surrounded (U) then
         Append (S, ASCII.LF & "<span foreground='#c00000'><b>SURROUNDED</b>"
                 & " - defence -2, no supply</span>");
      elsif Own and then T.Mover not in Air | Naval | Static then
         case Supply_Of (U) is
            when Supplied =>
               Append (S, ASCII.LF & "Supply: good");
            when Low_Supply =>
               Append (S, ASCII.LF & "<span foreground='#b07000'>Supply: "
                       & "low - partial resupply only</span>");
            when Cut_Off =>
               Append (S, ASCII.LF & "<span foreground='#c00000'><b>OUT OF "
                       & "SUPPLY</b> - fights at -1, no resupply"
                       & (if Get (U).Cut_Turns >= 1
                          then ", losing strength" else "")
                       & "</span>");
         end case;
      end if;
      if T.Charge or else T.Support or else T.Ignore_Entrench
        or else T.Bombard
      then
         Append (S, ASCII.LF & "<i>"
                 & (if T.Charge then "charge " else "")
                 & (if T.Support then "support-fire " else "")
                 & (if T.Bombard then "bombard " else "")
                 & (if T.Ignore_Entrench then "sapper" else "") & "</i>");
      end if;
      if Un.Side = G.Current and then Own then
         Append (S, ASCII.LF
                 & (if Un.Has_Attacked and then Un.Moves_Left = 0
                    then "Done for this turn"
                    elsif Un.Has_Attacked then "Has attacked"
                    elsif Un.Has_Moved then "Has moved"
                    else "Ready"));
         if Is_Air (T) and then Un.Fuel <= T.Movement then
            Append (S, ASCII.LF
                    & "<span foreground='#c03000'>Low fuel - land at an "
                    & "airfield or friendly town!</span>");
         end if;
      end if;
      return To_String (S);
   end Unit_Text;

   procedure Update_Panels is
      Sel : constant Natural := View.Selected;
   begin
      if not G.Loaded then
         Status_Label.Set_Markup ("<b>No scenario loaded</b>" & ASCII.LF
                                  & "Game > New scenario / New campaign");
         Btn_Undo.Set_Sensitive (False);
         Btn_Resupply.Set_Sensitive (False);
         Btn_Reinforce.Set_Sensitive (False);
         Btn_Buy.Set_Sensitive (False);
         Btn_Next.Set_Sensitive (False);
         Btn_End.Set_Sensitive (False);
         return;
      end if;
      if Editor.Active then
         Status_Label.Set_Markup
           ("<b>Scenario editor</b>" & ASCII.LF
            & Esc (To_String (G.Title)) & ASCII.LF
            & Esc (To_String (G.Era.Name)) & ",  map" & G.Cols'Image
            & " x" & G.Rows'Image);
         Unit_Label.Set_Markup (Esc (Editor.Help_Text));
         Btn_Resupply.Set_Sensitive (False);
         Btn_Reinforce.Set_Sensitive (False);
         Btn_Buy.Set_Sensitive (False);
         Btn_Undo.Set_Sensitive (False);
         Btn_Next.Set_Sensitive (False);
         Btn_End.Set_Sensitive (False);
         return;
      end if;
      Status_Label.Set_Markup
        ((if Engine.Campaign.C.Active
          then "<i>" & Esc (To_String (Engine.Campaign.C.Title))
               & ", battle " & Img (Engine.Campaign.Stage_Number)
               & "</i>" & ASCII.LF
          else "")
         & "<b>" & Esc (To_String (G.Title)) & "</b>" & ASCII.LF
         & Esc (To_String (G.Era.Name))
         & (if G.Fog then ", fog of war" else "") & ASCII.LF
         & "Turn " & Img (G.Turn) & " of " & Img (G.Max_Turns)
         & " - <b>" & Esc (To_String (G.Sides (G.Current).Name)) & "</b>"
         & (if G.Sides (G.Current).Control = Computer then " (computer)"
            else "") & ASCII.LF
         & "Prestige: " & Img (G.Sides (G.Current).Prestige) & ASCII.LF
         & "Weather: <b>" & Weather_Name (G.Weather) & "</b>"
         & (if G.Weather /= Fair
            then " <small>(" & Weather_Effects (G.Weather) & ")</small>"
            else "")
         & ", forecast " & Weather_Name (G.Forecast) & ASCII.LF
         & "Objectives: " & Esc (To_String (G.Sides (G.Attacker).Name))
         & " holds " & Img (Victory_Hexes_Owned (G.Attacker)) & " of "
         & Img (Victory_Hexes_Total));

      if Sel /= 0 and then Get (Sel).Alive then
         Unit_Label.Set_Markup (Unit_Text (Sel));
      elsif View.Deploy_Type /= 0 then
         Unit_Label.Set_Markup
           ("<b>Placing " & Esc (To_String (G.Types (View.Deploy_Type).Name))
            & "</b>" & ASCII.LF
            & "Click a green-outlined hex. Right-click to cancel.");
      else
         Unit_Label.Set_Markup ("<i>Click one of your units</i>");
      end if;

      Btn_Resupply.Set_Sensitive
        (Human_Turn and then Sel /= 0 and then Can_Resupply (Sel));
      Btn_Reinforce.Set_Sensitive
        (Human_Turn and then Sel /= 0 and then Can_Reinforce (Sel));
      Btn_Reinforce.Set_Label
        (if Sel /= 0 and then Get (Sel).Alive
           and then Get (Sel).Strength < Max_Strength
         then "Reinforce (" & Img (Reinforce_Cost (Sel)) & ")"
         else "Reinforce");
      Btn_Buy.Set_Sensitive (Human_Turn);
      Btn_Undo.Set_Sensitive (Human_Turn and then Can_Undo);
      Btn_Next.Set_Sensitive (Human_Turn);
      Btn_End.Set_Sensitive (Human_Turn);
   end Update_Panels;

   procedure Update_Hover_Info is
      H : constant Hex := View.Hover;
      S : Unbounded_String;
   begin
      if not G.Loaded or else H = No_Hex or else not In_Map (H) then
         Info_Label.Set_Markup ("");
         return;
      end if;
      declare
         Ce  : constant Cell := G.Cells (H.Col, H.Row);
         Sel : constant Natural := View.Selected;
         Tgt : constant Natural :=
           (if Sel /= 0 and then Get (Sel).Alive
            then Target_In (Sel, H) else No_Unit);
      begin
         Append (S, "<b>" & Name (Ce.Terrain) & "</b> " & Image (H));
         if Length (Ce.Name) > 0 then
            Append (S, "  " & Esc (To_String (Ce.Name)));
         end if;
         if Ce.Victory then
            Append (S, " <b>[objective]</b>");
         end if;
         Append (S, ASCII.LF & "Defence bonus "
                 & Img (Defense_Bonus (Ce.Terrain)));
         if Ce.Owner /= 0 then
            Append (S, "   Owner "
                    & Esc (To_String (G.Sides (Ce.Owner).Name)));
         end if;
         if View.Viewer /= 0 and then not Hex_Seen (H, View.Viewer) then
            Append (S, ASCII.LF & "<i>Not observed (fog of war)</i>");
         end if;
         if Tgt /= No_Unit then
            declare
               P : constant Prediction := Predict (Sel, Get (Sel).Pos, Tgt);
            begin
               Append (S, ASCII.LF
                       & "<span foreground='#b00000'><b>Attack "
                       & Esc (To_String (Type_Of (Tgt).Name))
                       & "!</b>" & ASCII.LF & "Expected losses: you "
                       & Fmt1 (P.Att_Loss) & ", enemy " & Fmt1 (P.Def_Loss)
                       & "</span>");
               if P.Support_Threat then
                  Append (S, ASCII.LF
                          & "<i>Enemy guns/flak may add support fire</i>");
               end if;
            end;
         elsif Sel /= 0 and then View.Show_Reach
           and then View.Reach.Cost (H.Col, H.Row) > 0
         then
            Append (S, ASCII.LF & "Move cost "
                    & Img (View.Reach.Cost (H.Col, H.Row)));
         end if;
         for U of Natural_Array'(Unit_At (H), Air_At (H)) loop
            if Shown (U) then
               Append (S, ASCII.LF & ASCII.LF & Unit_Text (U));
            end if;
         end loop;
      end;
      Info_Label.Set_Markup (To_String (S));
   end Update_Hover_Info;

   procedure Recompute_Reach is
   begin
      View.Show_Reach := False;
      if View.Selected /= 0 and then Get (View.Selected).Alive
        and then Get (View.Selected).Side = G.Current
        and then Human_Turn
      then
         Compute_Reach (View.Selected, View.Reach);
         View.Show_Reach := True;
      end if;
   end Recompute_Reach;

   procedure Show_Hints is
   begin
      if In_Dialog then
         return;
      end if;
      while not Pending_Hints.Is_Empty loop
         declare
            T : constant String := Pending_Hints.First_Element;
         begin
            Pending_Hints.Delete_First;
            Show_Message (Message_Info, T, "Hint");
         end;
      end loop;
   end Show_Hints;

   function Oob_Side return Side_Id is
     (if View.Viewer in Player_Side then View.Viewer else G.Current);

   procedure Refresh is
   begin
      View.Viewer := Viewer;
      Flush_Log;
      Update_Panels;
      Update_Hover_Info;
      Area.Queue_Draw;
      if Mini /= null then
         Mini.Queue_Draw;
      end if;
      if G.Loaded and then not Editor.Active then
         Oob_Window.Update (Oob_Side);
      end if;
   end Refresh;

   ------------------
   -- AI turn loop --
   ------------------

   procedure Start_AI_If_Needed;
   procedure After_Battle;

   procedure Check_Winner is
   begin
      if G.Winner /= 0 and then not Winner_Shown then
         Winner_Shown := True;
         Refresh;
         Show_Message
           (Message_Info,
            To_String (G.Victory_Grade) & " for "
            & To_String (G.Sides (G.Winner).Name) & "!"
            & ASCII.LF & ASCII.LF
            & "Objectives held by the attacker: "
            & Img (Victory_Hexes_Owned (G.Attacker)) & " of "
            & Img (Victory_Hexes_Total),
            "Battle over");
         After_Battle;
      end if;
   end Check_Winner;

   --  Hot seat with fog: hide the map while the other player takes over.
   procedure Hand_Over is
   begin
      if G.Winner = 0 and then G.Fog
        and then G.Sides (1).Control = Human
        and then G.Sides (2).Control = Human
      then
         View.Viewer := G.Current;
         View.Selected := 0;
         Show_Message (Message_Info,
                       "Hand over to " & To_String (G.Sides (G.Current).Name)
                       & "." & ASCII.LF & "The other player should look away!",
                       "Next player");
      end if;
   end Hand_Over;

   function AI_Tick return Boolean is
   begin
      if not AI_Running then
         return False;
      end if;
      if Anim.Busy then
         return True;          --  let the current animation finish
      end if;
      if G.Winner = 0 and then Engine.AI.Step then
         Anim.Enqueue (View.Viewer);
         Refresh;
         return True;
      end if;
      if G.Winner = 0 then
         End_Turn;
      end if;
      Anim.Enqueue (View.Viewer);
      AI_Running := False;
      AI_Source  := 0;
      View.Selected := 0;
      View.Last_Fight := No_Hex;
      Refresh;
      Check_Winner;
      Show_Hints;
      Start_AI_If_Needed;
      return False;
   end AI_Tick;

   procedure Start_AI_If_Needed is
   begin
      if G.Loaded and then G.Winner = 0
        and then G.Sides (G.Current).Control = Computer
        and then not AI_Running
      then
         AI_Running := True;
         Engine.AI.Begin_Turn;
         Refresh;
         AI_Source := Glib.Main.Timeout_Add (300, AI_Tick'Access);
      end if;
   end Start_AI_If_Needed;

   procedure Stop_AI is
   begin
      if AI_Running and then AI_Source /= 0 then
         Glib.Main.Remove (AI_Source);
      end if;
      AI_Running := False;
      AI_Source  := 0;
   end Stop_AI;

   procedure New_Game_Started is
      W, H : Gint;
   begin
      View := (others => <>);
      Winner_Shown := False;
      Anim.Clear;
      Effects.Clear;
      Fair_Item.Set_Active (G.Fair_AI);
      Log_Buffer.Set_Text ("");
      if Length (G.Description) > 0 then
         Messages.Prepend (To_String (G.Description));
      end if;
      Map_Size (W, H);
      Area.Set_Size_Request (W, H);
      Fog_Item.Set_Active (G.Fog);
      Refresh;
      Show_Hints;
      Start_AI_If_Needed;
   end New_Game_Started;

   procedure After_Battle is
      Report : Unbounded_String;
      More   : Boolean;
   begin
      if not Engine.Campaign.C.Active then
         return;
      end if;
      More := Engine.Campaign.Finish_Stage (Report);
      Show_Message (Message_Info, To_String (Report), "Campaign");
      if More then
         Campaign_HQ.Run (Win);
         Stop_AI;
         Engine.Campaign.Start_Stage;
         New_Game_Started;
      end if;
   end After_Battle;

   ------------
   -- Camera --
   ------------

   --  Scroll the map so that hex H is comfortably on screen.
   procedure Ensure_Visible (H : Hex) is
      Edge : constant Gdouble := 70.0;
   begin
      if H = No_Hex or else not In_Map (H) or else Map_Scroll = null then
         return;
      end if;
      declare
         HA : constant Gtk.Adjustment.Gtk_Adjustment :=
           Map_Scroll.Get_Hadjustment;
         VA : constant Gtk.Adjustment.Gtk_Adjustment :=
           Map_Scroll.Get_Vadjustment;
         X  : constant Gdouble := Center_X (H) * Zoom;
         Y  : constant Gdouble := Center_Y (H) * Zoom;
      begin
         if X < HA.Get_Value + Edge
           or else X > HA.Get_Value + HA.Get_Page_Size - Edge
         then
            HA.Set_Value (X - HA.Get_Page_Size / 2.0);
         end if;
         if Y < VA.Get_Value + Edge
           or else Y > VA.Get_Value + VA.Get_Page_Size - Edge
         then
            VA.Set_Value (Y - VA.Get_Page_Size / 2.0);
         end if;
      end;
   end Ensure_Visible;

   procedure Set_Zoom (Z : Gdouble) is
      W, H : Gint;
   begin
      Zoom := Gdouble'Max (Min_Zoom, Gdouble'Min (Max_Zoom, Z));
      Map_Size (W, H);
      Area.Set_Size_Request (W, H);
      Area.Queue_Draw;
      if View.Selected /= 0 and then Get (View.Selected).Alive then
         Ensure_Visible (Get (View.Selected).Pos);
      end if;
   end Set_Zoom;

   -------------
   -- Actions --
   -------------

   procedure Select_Unit (U : Natural) is
   begin
      View.Selected := U;
      View.Deploy_Type := 0;
      Recompute_Reach;
      if U /= 0 and then Human_Turn and then Get (U).Side = G.Current then
         Raise_Event ("select");
      end if;
      Refresh;
      Show_Hints;
   end Select_Unit;

   procedure After_Action is
   begin
      if View.Selected /= 0 and then not Get (View.Selected).Alive then
         View.Selected := 0;
      end if;
      Anim.Enqueue (View.Viewer);
      Recompute_Reach;
      Refresh;
      if not Anim.Busy then
         Show_Hints;
         Check_Winner;
      end if;
      --  otherwise Anim_Finished takes over when the animation ends
   end After_Action;

   procedure Anim_Redraw is
   begin
      Area.Queue_Draw;
   end Anim_Redraw;

   procedure Anim_Finished is
   begin
      Refresh;
      if not AI_Running then
         Show_Hints;
         Check_Winner;
      end if;
   end Anim_Finished;

   procedure Do_End_Turn is
   begin
      if not Human_Turn then
         return;
      end if;
      View.Selected := 0;
      View.Show_Reach := False;
      View.Last_Fight := No_Hex;
      View.Deploy_Type := 0;
      End_Turn;
      Anim.Enqueue (View.Viewer);
      Hand_Over;
      Refresh;
      Check_Winner;
      Show_Hints;
      Start_AI_If_Needed;
   end Do_End_Turn;

   procedure Do_Next_Unit is
      Start : constant Natural := View.Selected;
      N     : constant Natural := Natural (G.Units.Length);
      I     : Natural := Start;
   begin
      if not Human_Turn or else N = 0 then
         return;
      end if;
      for K in 1 .. N loop
         I := (if I >= N then 1 else I + 1);
         declare
            U : constant Unit := Get (I);
         begin
            if U.Alive and then U.Side = G.Current
              and then (U.Moves_Left > 0 or else not U.Has_Attacked)
              and then I /= Start
            then
               Select_Unit (I);
               Ensure_Visible (U.Pos);
               return;
            end if;
         end;
         pragma Unreferenced (K);
      end loop;
   end Do_Next_Unit;

   procedure On_Resupply (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      if Human_Turn and then View.Selected /= 0 then
         Resupply (View.Selected);
         After_Action;
      end if;
   end On_Resupply;

   procedure On_Reinforce (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      if Human_Turn and then View.Selected /= 0 then
         Reinforce (View.Selected);
         After_Action;
      end if;
   end On_Reinforce;

   procedure Do_Undo is
   begin
      if Human_Turn and then Can_Undo then
         Undo_Move;
         Recompute_Reach;
         Refresh;
      end if;
   end Do_Undo;

   procedure On_Undo (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Do_Undo;
   end On_Undo;

   procedure On_Next (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Do_Next_Unit;
   end On_Next;

   procedure On_End (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Do_End_Turn;
   end On_End;

   ----------------
   -- Buy dialog --
   ----------------

   Buy_Types : array (1 .. 64) of Natural;
   Buy_Count : Natural := 0;
   Buy_Info  : Gtk_Label;

   function Type_Summary (T : Type_Index) return String is
      Ty : constant Unit_Type := G.Types (T);
   begin
      return "<b>" & Esc (To_String (Ty.Name)) & "</b> - "
        & Class_Name (Ty.Class) & ASCII.LF
        & "Cost " & Img (Ty.Cost) & "   Move " & Img (Ty.Movement)
        & "   Range " & Img (Ty.Max_Range) & ASCII.LF
        & "Attack soft " & Img (Ty.Soft_Attack) & " / hard "
        & Img (Ty.Hard_Attack) & " / air " & Img (Ty.Air_Attack)
        & "   Defence " & Img (Ty.Defense) & ASCII.LF
        & (if Is_Air (Ty)
           then "Aircraft: deploys at an airfield or city."
           else "Deploys in a friendly town, city or airfield.");
   end Type_Summary;

   procedure Buy_Changed
     (C : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      I : constant Gint := C.Get_Active;
   begin
      if I >= 0 and then Natural (I) < Buy_Count then
         Buy_Info.Set_Markup (Type_Summary (Buy_Types (Natural (I) + 1)));
      end if;
   end Buy_Changed;

   procedure On_Buy (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
      Side  : constant Player_Side := G.Current;
      Dlg   : Gtk_Dialog;
      Combo : Gtk_Combo_Box_Text;
      Dummy : Gtk_Widget;
      Resp  : Gtk_Response_Type;
   begin
      if not Human_Turn then
         return;
      end if;
      Buy_Count := 0;
      for T in G.Types.First_Index .. G.Types.Last_Index loop
         if May_Buy (T, Side) and then Buy_Count < Buy_Types'Last then
            Buy_Count := Buy_Count + 1;
            Buy_Types (Buy_Count) := T;
         end if;
      end loop;
      if Buy_Count = 0 then
         Show_Message (Message_Info,
                       "No reinforcements are available in this scenario.");
         return;
      end if;

      Gtk_New (Dlg, "Buy unit", Win, Modal);
      Gtk_New (Combo);
      for I in 1 .. Buy_Count loop
         declare
            Ty : constant Unit_Type := G.Types (Buy_Types (I));
         begin
            Combo.Append_Text (To_String (Ty.Name) & "  (" & Img (Ty.Cost)
                               & ")"
                               & (if Ty.Cost > G.Sides (Side).Prestige
                                  then "  - too expensive"
                                  elsif not Has_Deploy_Hex (Buy_Types (I),
                                                            Side)
                                  then "  - no place to deploy"
                                  else ""));
         end;
      end loop;
      Gtk_New (Buy_Info);
      Buy_Info.Set_Alignment (0.0, 0.0);
      Combo.On_Changed (Buy_Changed'Access);
      Combo.Set_Active (0);
      declare
         Head : Gtk_Label;
      begin
         Gtk_New (Head);
         Head.Set_Markup ("Available prestige: <b>"
                          & Img (G.Sides (Side).Prestige) & "</b>");
         Dlg.Get_Content_Area.Pack_Start (Head, False, False, 0);
      end;
      Dlg.Get_Content_Area.Set_Spacing (8);
      Dlg.Get_Content_Area.Set_Border_Width (10);
      Dlg.Get_Content_Area.Pack_Start (Combo, False, False, 0);
      Dlg.Get_Content_Area.Pack_Start (Buy_Info, True, True, 0);
      Dummy := Dlg.Add_Button ("Cancel", Gtk_Response_Cancel);
      Dummy := Dlg.Add_Button ("Choose location", Gtk_Response_Accept);
      Dlg.Show_All;
      In_Dialog := True;
      Resp := Dlg.Run;
      In_Dialog := False;
      if Resp = Gtk_Response_Accept and then Combo.Get_Active >= 0 then
         declare
            T : constant Type_Index :=
              Buy_Types (Natural (Combo.Get_Active) + 1);
         begin
            Dlg.Destroy;
            if G.Types (T).Cost > G.Sides (Side).Prestige then
               Show_Message (Message_Warning, "Not enough prestige.");
            elsif not Has_Deploy_Hex (T, Side) then
               Show_Message (Message_Warning,
                             "No free friendly town/airfield to deploy in.");
            else
               View.Selected := 0;
               View.Show_Reach := False;
               View.Deploy_Type := T;
               Refresh;
            end if;
            return;
         end;
      end if;
      Dlg.Destroy;
   end On_Buy;

   ---------------------
   -- Order of battle --
   ---------------------

   procedure Oob_Picked (U : Positive) is
   begin
      if not Get (U).Alive then
         return;
      end if;
      Ensure_Visible (Get (U).Pos);
      if Human_Turn and then Get (U).Side = G.Current then
         Select_Unit (U);
      else
         View.Hover := Get (U).Pos;
         Refresh;
      end if;
   end Oob_Picked;

   procedure Show_Oob is
   begin
      if G.Loaded and then not Editor.Active then
         Oob_Window.On_Pick := Oob_Picked'Access;
         Oob_Window.Show (Win, Oob_Side);
      end if;
   end Show_Oob;

   -------------
   -- Minimap --
   -------------

   function Mini_Draw (W : access Gtk_Widget_Record'Class;
                       Cr : Cairo.Cairo_Context) return Boolean
   is
      HA : constant Gtk.Adjustment.Gtk_Adjustment :=
        Map_Scroll.Get_Hadjustment;
      VA : constant Gtk.Adjustment.Gtk_Adjustment :=
        Map_Scroll.Get_Vadjustment;
   begin
      Draw_Minimap
        (Cr, Gdouble (W.Get_Allocated_Width),
         Gdouble (W.Get_Allocated_Height), View.Viewer,
         HA.Get_Value / Zoom, VA.Get_Value / Zoom,
         HA.Get_Page_Size / Zoom, VA.Get_Page_Size / Zoom);
      return True;
   end Mini_Draw;

   procedure Mini_Jump (W : access Gtk_Widget_Record'Class;
                        MX, MY : Gdouble) is
      X, Y : Gdouble;
      HA : constant Gtk.Adjustment.Gtk_Adjustment :=
        Map_Scroll.Get_Hadjustment;
      VA : constant Gtk.Adjustment.Gtk_Adjustment :=
        Map_Scroll.Get_Vadjustment;
   begin
      if not G.Loaded then
         return;
      end if;
      Minimap_To_Map (MX, MY, Gdouble (W.Get_Allocated_Width),
                      Gdouble (W.Get_Allocated_Height), X, Y);
      HA.Set_Value (X * Zoom - HA.Get_Page_Size / 2.0);
      VA.Set_Value (Y * Zoom - VA.Get_Page_Size / 2.0);
      Mini.Queue_Draw;
   end Mini_Jump;

   function Mini_Press (W : access Gtk_Widget_Record'Class;
                        Event : Gdk_Event_Button) return Boolean is
   begin
      Mini_Jump (W, Event.X, Event.Y);
      return True;
   end Mini_Press;

   function Mini_Motion (W : access Gtk_Widget_Record'Class;
                         Event : Gdk_Event_Motion) return Boolean is
   begin
      if (Event.State and Button1_Mask) /= 0 then
         Mini_Jump (W, Event.X, Event.Y);
      end if;
      return True;
   end Mini_Motion;

   procedure Scrolled (A : access Gtk.Adjustment.Gtk_Adjustment_Record'Class)
   is
      pragma Unreferenced (A);
   begin
      if Mini /= null then
         Mini.Queue_Draw;
      end if;
   end Scrolled;

   ------------------
   -- Map handlers --
   ------------------

   function On_Draw (W : access Gtk_Widget_Record'Class;
                     Cr : Cairo.Cairo_Context) return Boolean is
      pragma Unreferenced (W);
   begin
      Draw (Cr, View);
      return True;
   end On_Draw;

   --  Which unit in hex H should a click select?
   function Pick_Unit (H : Hex) return Natural is
      Gr : constant Natural :=
        (if Shown (Unit_At (H)) then Unit_At (H) else 0);
      Ai : constant Natural :=
        (if Shown (Air_At (H)) then Air_At (H) else 0);
   begin
      if Gr /= 0 and then Ai /= 0 then
         --  Clicking again toggles between ground and air.
         if View.Selected = Gr then
            return Ai;
         elsif View.Selected = Ai then
            return Gr;
         elsif Get (Ai).Side = G.Current and then Get (Gr).Side /= G.Current
         then
            return Ai;
         end if;
         return Gr;
      end if;
      return (if Gr /= 0 then Gr else Ai);
   end Pick_Unit;

   function On_Click (W : access Gtk_Widget_Record'Class;
                      Event : Gdk_Event_Button) return Boolean is
      pragma Unreferenced (W);
      H   : constant Hex := Hex_At (Event.X, Event.Y);
      Sel : constant Natural := View.Selected;
   begin
      if Editor.Active then
         if H /= No_Hex and then Event.The_Type = Button_Press then
            Editor.Click (H, Event.Button);
         end if;
         return True;
      end if;
      if not G.Loaded or else Event.The_Type /= Button_Press
        or else Anim.Busy
      then
         return True;
      end if;
      if View.Deploy_Type /= 0 then
         if Event.Button = 1 and then H /= No_Hex
           and then Can_Deploy (View.Deploy_Type, G.Current, H)
         then
            Buy (View.Deploy_Type, G.Current, H);
         end if;
         View.Deploy_Type := 0;
         After_Action;
         return True;
      end if;
      if Event.Button = 3 or else H = No_Hex then
         Select_Unit (0);
         return True;
      end if;

      if Human_Turn and then Sel /= 0 and then Get (Sel).Alive
        and then Get (Sel).Side = G.Current
      then
         declare
            T : constant Natural := Target_In (Sel, H);
         begin
            if T /= No_Unit then
               View.Last_Fight := H;
               Attack (Sel, T);
               After_Action;
               return True;
            elsif View.Show_Reach and then Can_Move_To (Sel, View.Reach, H)
            then
               Move_Unit_Undoable (Sel, H, View.Reach);
               After_Action;
               return True;
            end if;
         end;
      end if;
      Select_Unit (Pick_Unit (H));
      return True;
   end On_Click;

   function On_Motion (W : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Motion) return Boolean is
      pragma Unreferenced (W);
      H : constant Hex := Hex_At (Event.X, Event.Y);
   begin
      if H /= View.Hover then
         View.Hover := H;
         if Editor.Active and then H /= No_Hex
           and then (Event.State and Button1_Mask) /= 0
         then
            Editor.Drag (H);
         end if;
         Update_Hover_Info;
         Area.Queue_Draw;
      end if;
      return True;
   end On_Motion;

   --  Ctrl + mouse wheel zooms; plain wheel scrolls the map as usual.
   function On_Scroll (W : access Gtk_Widget_Record'Class;
                       Event : Gdk_Event_Scroll) return Boolean is
      pragma Unreferenced (W);
   begin
      if (Event.State and Control_Mask) = 0 then
         return False;
      end if;
      if Event.Direction = Scroll_Up
        or else (Event.Direction = Scroll_Smooth and then Event.Delta_Y < 0.0)
      then
         Set_Zoom (Zoom * 1.1);
      elsif Event.Direction = Scroll_Down
        or else (Event.Direction = Scroll_Smooth and then Event.Delta_Y > 0.0)
      then
         Set_Zoom (Zoom / 1.1);
      end if;
      return True;
   end On_Scroll;

   function On_Key (W : access Gtk_Widget_Record'Class;
                    Event : Gdk_Event_Key) return Boolean is
      pragma Unreferenced (W);
   begin
      if Event.Keyval = GDK_LC_n or else Event.Keyval = GDK_space then
         Do_Next_Unit;
         return True;
      elsif Event.Keyval = GDK_Escape then
         Select_Unit (0);
         return True;
      elsif Event.Keyval in GDK_plus | GDK_equal | GDK_KP_Add then
         Set_Zoom (Zoom * 1.15);
         return True;
      elsif Event.Keyval in GDK_minus | GDK_KP_Subtract then
         Set_Zoom (Zoom / 1.15);
         return True;
      elsif Event.Keyval = GDK_0 then
         Set_Zoom (1.0);
         return True;
      elsif Event.Keyval = GDK_F2 then
         Show_Oob;
         return True;
      elsif Event.Keyval = GDK_LC_s
        and then (Event.State and Control_Mask) = 0
      then
         Supply_Item.Set_Active (not Supply_Item.Get_Active);
         return True;
      elsif Event.Keyval = GDK_LC_e
        and then (Event.State and Control_Mask) /= 0
      then
         Do_End_Turn;
         return True;
      elsif Event.Keyval = GDK_LC_z
        and then (Event.State and Control_Mask) /= 0
      then
         Do_Undo;
         return True;
      end if;
      return False;
   end On_Key;

   -----------------------
   -- Scenario handling --
   -----------------------

   type Play_Mode is (Play_Side_1, Play_Side_2, Hot_Seat, Watch);
   Chosen_Difficulty : Difficulty_Level := Normal;

   procedure Start_Scenario (Path : String; Mode : Play_Mode) is
   begin
      Stop_AI;
      Engine.Campaign.Stop;
      Engine.Loader.Load_Scenario (Path);
      G.Sides (1).Control :=
        (if Mode in Play_Side_1 | Hot_Seat then Human else Computer);
      G.Sides (2).Control :=
        (if Mode in Play_Side_2 | Hot_Seat then Human else Computer);
      Apply_Difficulty (Chosen_Difficulty);
      --  Turn-1 hints were queued for the scenario's default players.
      if G.Sides (G.Current).Control /= Human then
         Pending_Hints.Clear;
         for H of G.Hints loop
            H.Shown := False;
         end loop;
      end if;
      New_Game_Started;
   exception
      when E : Engine.Loader.Load_Error | Constraint_Error =>
         Show_Message (Message_Error, "Could not load scenario:" & ASCII.LF
                       & Ada.Exceptions.Exception_Message (E));
   end Start_Scenario;

   Desc_Target  : Gtk_Label;
   Desc_List    : Engine.Loader.Info_Vectors.Vector;
   Preview_Area : Gtk_Drawing_Area;
   Preview      : Engine.Loader.Preview_Data;

   function Preview_Draw (W : access Gtk_Widget_Record'Class;
                          Cr : Cairo.Cairo_Context) return Boolean is
   begin
      Draw_Preview (Cr, Preview, Gdouble (W.Get_Allocated_Width),
                    Gdouble (W.Get_Allocated_Height));
      return True;
   end Preview_Draw;

   procedure Combo_Changed
     (C : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      I : constant Gint := C.Get_Active;
   begin
      if I >= 0 and then Natural (I) < Natural (Desc_List.Length) then
         declare
            Info : constant Engine.Loader.Scenario_Info :=
              Desc_List (Positive (I + 1));
         begin
            Engine.Loader.Read_Preview (To_String (Info.Preview), Preview);
            Desc_Target.Set_Markup
              (Esc (To_String (Info.Description))
               & (if Preview.Ok
                  then ASCII.LF & ASCII.LF & "<b>"
                       & Esc (To_String (Preview.Names (1))) & "</b> vs <b>"
                       & Esc (To_String (Preview.Names (2))) & "</b>,"
                       & Preview.Turns'Image & " turns, map"
                       & Preview.Cols'Image & " x" & Preview.Rows'Image
                  else ""));
         end;
         if Preview_Area /= null then
            Preview_Area.Queue_Draw;
         end if;
      end if;
   end Combo_Changed;

   --  Generic chooser; returns index into Desc_List (0 = cancelled) and
   --  the play mode if With_Mode.
   procedure Choose
     (Title : String; With_Mode : Boolean;
      Index : out Natural; Mode : out Play_Mode)
   is
      Dlg    : Gtk_Dialog;
      Combo  : Gtk_Combo_Box_Text;
      Mode_C : Gtk_Combo_Box_Text;
      Diff_C : Gtk_Combo_Box_Text;
      Dummy  : Gtk_Widget;
      Resp   : Gtk_Response_Type;
   begin
      Index := 0;
      Mode  := Play_Side_1;
      Gtk_New (Dlg, Title, Win, Modal);
      Dlg.Set_Default_Size (640, 560);
      Gtk_New (Preview_Area);
      Preview_Area.Set_Size_Request (600, 320);
      Preview_Area.On_Draw (Preview_Draw'Access);
      Gtk_New (Combo);
      for I of Desc_List loop
         Combo.Append_Text
           ((if Length (I.Category) > 0
             then "[" & To_String (I.Category) & "]  "
             elsif Length (I.Era) > 0 then "[" & To_String (I.Era) & "]  "
             else "")
            & To_String (I.Title));
      end loop;
      Gtk_New (Desc_Target, "");
      Desc_Target.Set_Line_Wrap (True);
      Desc_Target.Set_Max_Width_Chars (64);
      Desc_Target.Set_Alignment (0.0, 0.0);
      Combo.On_Changed (Combo_Changed'Access);
      Combo.Set_Active (0);

      Dlg.Get_Content_Area.Set_Spacing (8);
      Dlg.Get_Content_Area.Set_Border_Width (10);
      Dlg.Get_Content_Area.Pack_Start (Combo, False, False, 0);
      Dlg.Get_Content_Area.Pack_Start (Preview_Area, True, True, 0);
      Dlg.Get_Content_Area.Pack_Start (Desc_Target, False, False, 0);
      if With_Mode then
         Gtk_New (Mode_C);
         Mode_C.Append_Text ("Play the attacking side (side 1) vs computer");
         Mode_C.Append_Text ("Play the defending side (side 2) vs computer");
         Mode_C.Append_Text ("Two players, hot seat");
         Mode_C.Append_Text ("Watch computer vs computer");
         Mode_C.Set_Active (0);
         Dlg.Get_Content_Area.Pack_Start (Mode_C, False, False, 0);
      end if;
      Gtk_New (Diff_C);
      Diff_C.Append_Text ("Easy - more prestige, weaker opposition");
      Diff_C.Append_Text ("Normal");
      Diff_C.Append_Text ("Hard - less prestige, veteran enemy");
      Diff_C.Set_Active (Gint (Difficulty_Level'Pos (Chosen_Difficulty)));
      Dlg.Get_Content_Area.Pack_Start (Diff_C, False, False, 0);
      Dummy := Dlg.Add_Button ("Cancel", Gtk_Response_Cancel);
      Dummy := Dlg.Add_Button ("Start", Gtk_Response_Accept);
      Dlg.Set_Default_Response (Gtk_Response_Accept);

      Dlg.Show_All;
      In_Dialog := True;
      Resp := Dlg.Run;
      In_Dialog := False;
      if Resp = Gtk_Response_Accept and then Combo.Get_Active >= 0 then
         Index := Natural (Combo.Get_Active) + 1;
         Chosen_Difficulty := Difficulty_Level'Val
           (Integer'Max (0, Integer (Diff_C.Get_Active)));
         if With_Mode then
            Mode := Play_Mode'Val (Integer'Max (0,
                                   Integer (Mode_C.Get_Active)));
         end if;
      end if;
      Dlg.Destroy;
      Preview_Area := null;
   end Choose;

   procedure Choose_Scenario is
      I : Natural;
      M : Play_Mode;
   begin
      Desc_List := Engine.Loader.List_Scenarios;
      if Desc_List.Is_Empty then
         Show_Message (Message_Error, "No scenarios found in "
                       & Engine.Loader.Data_Dir & "/scenarios");
         return;
      end if;
      Choose ("New scenario", True, I, M);
      if I /= 0 then
         Start_Scenario (To_String (Desc_List (I).Path), M);
      end if;
   end Choose_Scenario;

   procedure Choose_Campaign is
      I : Natural;
      M : Play_Mode;
   begin
      Desc_List := Engine.Campaign.List_Campaigns;
      if Desc_List.Is_Empty then
         Show_Message (Message_Error, "No campaigns found in "
                       & Engine.Loader.Data_Dir & "/campaigns");
         return;
      end if;
      Choose ("New campaign", False, I, M);
      if I /= 0 then
         Stop_AI;
         Engine.Campaign.C.Difficulty := Chosen_Difficulty;
         Engine.Campaign.Load_Campaign (To_String (Desc_List (I).Path));
         Engine.Campaign.Start_Stage;
         New_Game_Started;
      end if;
   exception
      when E : others =>
         Show_Message (Message_Error, "Could not start campaign:" & ASCII.LF
                       & Ada.Exceptions.Exception_Message (E));
   end Choose_Campaign;

   -----------------
   -- Save / load --
   -----------------

   function Ask_File (Saving : Boolean) return String is
      Dlg    : Gtk_File_Chooser_Dialog;
      Filter : Gtk_File_Filter;
      Dummy  : Gtk_Widget;
      Ok     : Boolean;
      pragma Unreferenced (Ok);
   begin
      Gtk_New (Dlg, (if Saving then "Save game" else "Load game"), Win,
               (if Saving then Gtk.File_Chooser.Action_Save
                else Gtk.File_Chooser.Action_Open));
      Ok := Dlg.Set_Current_Folder (Engine.Save.Save_Dir);
      Gtk_New (Filter);
      Filter.Set_Name ("Hexfront saves");
      Filter.Add_Pattern ("*.sav");
      Dlg.Add_Filter (Filter);
      if Saving then
         Dlg.Set_Do_Overwrite_Confirmation (True);
         Dlg.Set_Current_Name ("turn" & Img (G.Turn) & ".sav");
      end if;
      Dummy := Dlg.Add_Button ("Cancel", Gtk_Response_Cancel);
      Dummy := Dlg.Add_Button ((if Saving then "Save" else "Load"),
                               Gtk_Response_Accept);
      In_Dialog := True;
      if Dlg.Run = Gtk_Response_Accept then
         declare
            F : constant String := Dlg.Get_Filename;
         begin
            In_Dialog := False;
            Dlg.Destroy;
            if Saving and then Ada.Directories.Extension (F) /= "sav" then
               return F & ".sav";
            end if;
            return F;
         end;
      end if;
      In_Dialog := False;
      Dlg.Destroy;
      return "";
   end Ask_File;

   procedure Do_Save is
   begin
      if not Human_Turn then
         Show_Message (Message_Warning,
                       "You can save during your own turn.");
         return;
      end if;
      declare
         F : constant String := Ask_File (Saving => True);
      begin
         if F /= "" then
            Engine.Save.Save_Game (F);
            Log ("Game saved to " & F);
            Refresh;
         end if;
      end;
   exception
      when E : others =>
         Show_Message (Message_Error, "Save failed: "
                       & Ada.Exceptions.Exception_Message (E));
   end Do_Save;

   procedure Do_Load is
      F : constant String := Ask_File (Saving => False);
   begin
      if F /= "" then
         Stop_AI;
         Engine.Save.Load_Game (F);
         New_Game_Started;
      end if;
   exception
      when E : others =>
         Show_Message (Message_Error, "Load failed: "
                       & Ada.Exceptions.Exception_Message (E));
   end Do_Load;

   ----------
   -- Menu --
   ----------

   Help_Text : constant String :=
     "HEXFRONT - how to play" & ASCII.LF & ASCII.LF
     & "New to wargames? Start with the Boot Camp tutorial scenario."
     & ASCII.LF & ASCII.LF
     & "Left-click one of your units to select it. Hexes it cannot reach "
     & "are darkened; enemies it can attack are outlined in red. Click a "
     & "free hex to move, or a red-outlined enemy to attack. Hover over "
     & "an enemy to see the expected losses first. Click a hex twice to "
     & "switch between the ground unit and the aircraft above it."
     & ASCII.LF & ASCII.LF
     & "A unit may move and then attack. Artillery cannot fire after "
     & "moving, but supports nearby friends with defensive fire. "
     & "Recon units and aircraft may split their move. Entering a hex "
     & "next to an enemy (its zone of control) ends movement."
     & ASCII.LF & ASCII.LF
     & "Fog of war: you only see what your units can spot. Moving into a "
     & "hidden enemy is an ambush and ends the move." & ASCII.LF & ASCII.LF
     & "Units that do not move dig in. Units that have neither moved nor "
     & "fought may Resupply or Reinforce (costs prestige). Buy unit places "
     & "new forces in friendly towns and airfields. Aircraft must return to "
     & "an airfield or friendly town to refuel, or they crash."
     & ASCII.LF & ASCII.LF
     & "The attacker must capture every objective (gold-ringed hex) "
     & "before the turn limit; the defender wins by holding one."
     & ASCII.LF & ASCII.LF
     & "Keys: N / Space = next unit, Esc = deselect, Ctrl+E = end turn, "
     & "Ctrl+Z = undo move, + / - / 0 = zoom (also Ctrl+mouse wheel). "
     & "Right-click deselects or cancels." & ASCII.LF & ASCII.LF
     & "A unit with no way out (all neighbours enemy-held, impassable or in "
     & "an enemy zone of control) is SURROUNDED: defence -2 and no supply."
     & ASCII.LF & ASCII.LF
     & "Supply flows from your towns, cities, fortresses and airfields and "
     & "from your own map edge, but not through enemy units or their zones "
     & "of control. Units far from it are on low supply (partial resupply); "
     & "units cut off fight at -1, cannot resupply and lose strength every "
     & "turn after the first. View > Show supply lines (S) shades the map."
     & ASCII.LF & ASCII.LF
     & "Weather: rain, snow and fog ground all aircraft; mud slows vehicles "
     & "and snow slows everybody off the roads; bad weather shortens sight "
     & "and ranged fire. Check the forecast in the status panel."
     & ASCII.LF & ASCII.LF
     & "F2 opens the order of battle; click the minimap to jump around.";

   procedure On_New (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Choose_Scenario;
   end On_New;

   procedure On_Campaign (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Choose_Campaign;
   end On_Campaign;

   procedure On_Save (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Do_Save;
   end On_Save;

   procedure On_Load (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Do_Load;
   end On_Load;

   procedure On_Fog (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      if G.Loaded then
         G.Fog := M.Get_Active;
         Update_Vision;
         Recompute_Reach;
         Refresh;
      end if;
   end On_Fog;

   procedure Editor_Changed is
      W, H : Gint;
   begin
      View.Selected := 0;
      View.Show_Reach := False;
      Map_Size (W, H);
      Area.Set_Size_Request (W, H);
      Refresh;
   end Editor_Changed;

   procedure Editor_Test (Path : String) is
   begin
      Start_Scenario (Path, Play_Side_1);
   end Editor_Test;

   procedure Editor_Closed is
   begin
      G.Loaded := False;
      View := (others => <>);
      Refresh;
   end Editor_Closed;

   procedure On_Editor (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Stop_AI;
      Anim.Clear;
      Engine.Campaign.Stop;
      Editor.On_Changed := Editor_Changed'Access;
      Editor.On_Test    := Editor_Test'Access;
      Editor.On_Close   := Editor_Closed'Access;
      Editor.Open (Win);
   end On_Editor;

   procedure On_Fair (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      G.Fair_AI := M.Get_Active;
   end On_Fair;

   procedure On_Sound (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Sound.Enabled := M.Get_Active;
   end On_Sound;

   procedure On_Animate (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Anim.Enabled := M.Get_Active;
   end On_Animate;

   procedure On_Zoom_In (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Set_Zoom (Zoom * 1.15);
   end On_Zoom_In;

   procedure On_Zoom_Out (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Set_Zoom (Zoom / 1.15);
   end On_Zoom_Out;

   procedure On_Zoom_Reset (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Set_Zoom (1.0);
   end On_Zoom_Reset;

   procedure On_Zoom_Fit (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
      W, H : Gint;
   begin
      Zoom := 1.0;
      Map_Size (W, H);
      Set_Zoom (Gdouble'Min
                  (Gdouble (Map_Scroll.Get_Allocated_Width) / Gdouble (W),
                   Gdouble (Map_Scroll.Get_Allocated_Height) / Gdouble (H)));
   end On_Zoom_Fit;

   procedure On_Supply (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      View.Show_Supply := M.Get_Active;
      Area.Queue_Draw;
   end On_Supply;

   procedure On_Silhouettes (M : access Gtk_Check_Menu_Item_Record'Class) is
   begin
      Silhouettes := M.Get_Active;
      Area.Queue_Draw;
   end On_Silhouettes;

   procedure On_Oob (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Show_Oob;
   end On_Oob;

   procedure On_Quit (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Stop_AI;
      Gtk.Main.Main_Quit;
   end On_Quit;

   procedure On_Help (M : access Gtk_Menu_Item_Record'Class) is
      pragma Unreferenced (M);
   begin
      Show_Message (Message_Info, Help_Text, "How to play");
   end On_Help;

   procedure On_Destroy (W : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (W);
   begin
      Stop_AI;
      Gtk.Main.Main_Quit;
   end On_Destroy;

   --  hexfront [scenario.scn [side1|side2|hotseat|watch]]
   function Startup return Boolean is
      use Ada.Command_Line;
   begin
      if Argument_Count >= 1 then
         declare
            M : constant String :=
              (if Argument_Count >= 2 then Argument (2) else "side1");
         begin
            Start_Scenario
              (Argument (1),
               (if M = "side2" then Play_Side_2
                elsif M = "hotseat" then Hot_Seat
                elsif M = "watch" then Watch
                else Play_Side_1));
         end;
      else
         Choose_Scenario;
      end if;
      return False;
   end Startup;

   ------------
   -- Create --
   ------------

   procedure Create is
      VBox, Panel : Gtk_Box;
      Paned       : Gtk_Paned;
      Scroll      : Gtk_Scrolled_Window;
      Log_Scroll  : Gtk_Scrolled_Window;
      Bar         : Gtk_Menu_Bar;
      Menu        : Gtk_Menu;
      Item, Sub   : Gtk_Menu_Item;
      Sep         : Gtk_Separator_Menu_Item;
      Frame       : Gtk_Frame;
      Buttons     : Gtk_Box;
      Iter        : Gtk_Text_Iter;
      Id          : Glib.Main.G_Source_Id;
      pragma Unreferenced (Id);

      procedure Add (Label : String; CB : Cb_Gtk_Menu_Item_Void) is
      begin
         Gtk_New_With_Mnemonic (Sub, Label);
         Sub.On_Activate (CB);
         Menu.Append (Sub);
      end Add;
   begin
      Gtk_New (Win);
      Win.Set_Title ("Hexfront - operational wargame");
      Win.Set_Default_Size (1280, 820);
      declare
         Icon : constant String :=
           Engine.Loader.Data_Dir & "/icons/hexfront.svg";
      begin
         if not Ada.Directories.Exists (Icon)
           or else not Win.Set_Icon_From_File (Icon)
         then
            Win.Set_Icon_Name ("hexfront");
         end if;
      end;
      Win.On_Destroy (On_Destroy'Access);
      Win.On_Key_Press_Event (On_Key'Access);

      Gtk_New_Vbox (VBox);
      Win.Add (VBox);

      --  Menu bar
      Gtk_New (Bar);
      VBox.Pack_Start (Bar, False, False, 0);
      Gtk_New_With_Mnemonic (Item, "_Game");
      Bar.Append (Item);
      Gtk_New (Menu);
      Item.Set_Submenu (Menu);
      Add ("_New scenario...", On_New'Access);
      Add ("New _campaign...", On_Campaign'Access);
      Gtk_New (Sep);
      Menu.Append (Sep);
      Add ("Scenario _editor...", On_Editor'Access);
      Gtk_New (Sep);
      Menu.Append (Sep);
      Add ("_Save game...", On_Save'Access);
      Add ("_Load game...", On_Load'Access);
      Gtk_New (Sep);
      Menu.Append (Sep);
      Gtk_New (Fog_Item, "Fog of war");
      Fog_Item.Set_Active (True);
      Fog_Item.On_Toggled (On_Fog'Access);
      Menu.Append (Fog_Item);
      Gtk_New (Fair_Item, "Computer obeys fog of war");
      Fair_Item.Set_Active (True);
      Fair_Item.On_Toggled (On_Fair'Access);
      Menu.Append (Fair_Item);
      declare
         C : Gtk_Check_Menu_Item;
      begin
         Gtk_New (C, "Sound");
         C.Set_Active (True);
         C.On_Toggled (On_Sound'Access);
         Menu.Append (C);
         Gtk_New (C, "Animations");
         C.Set_Active (True);
         C.On_Toggled (On_Animate'Access);
         Menu.Append (C);
      end;
      Gtk_New (Sep);
      Menu.Append (Sep);
      Add ("_Quit", On_Quit'Access);

      Gtk_New_With_Mnemonic (Item, "_View");
      Bar.Append (Item);
      Gtk_New (Menu);
      Item.Set_Submenu (Menu);
      Add ("Zoom _in   (+)", On_Zoom_In'Access);
      Add ("Zoom _out   (-)", On_Zoom_Out'Access);
      Add ("_Normal size   (0)", On_Zoom_Reset'Access);
      Add ("_Fit map to window", On_Zoom_Fit'Access);
      Gtk_New (Sep);
      Menu.Append (Sep);
      Gtk_New (Supply_Item, "Show _supply lines   (S)");
      Supply_Item.Set_Use_Underline (True);
      Supply_Item.On_Toggled (On_Supply'Access);
      Menu.Append (Supply_Item);
      declare
         C : Gtk_Check_Menu_Item;
      begin
         Gtk_New (C, "Unit _silhouettes");
         C.Set_Use_Underline (True);
         C.On_Toggled (On_Silhouettes'Access);
         Menu.Append (C);
      end;
      Gtk_New (Sep);
      Menu.Append (Sep);
      Add ("_Order of battle   (F2)", On_Oob'Access);

      Gtk_New_With_Mnemonic (Item, "_Help");
      Bar.Append (Item);
      Gtk_New (Menu);
      Item.Set_Submenu (Menu);
      Add ("_How to play", On_Help'Access);

      Gtk_New_Hpaned (Paned);
      VBox.Pack_Start (Paned, True, True, 0);

      --  Map
      Gtk_New (Scroll);
      Map_Scroll := Scroll;
      Scroll.Set_Policy (Policy_Automatic, Policy_Automatic);
      Gtk_New (Area);
      Area.Set_Size_Request (400, 300);
      Area.Add_Events (Button_Press_Mask or Pointer_Motion_Mask
                       or Scroll_Mask or Smooth_Scroll_Mask);
      Area.On_Scroll_Event (On_Scroll'Access);
      Area.On_Draw (On_Draw'Access);
      Area.On_Button_Press_Event (On_Click'Access);
      Area.On_Motion_Notify_Event (On_Motion'Access);
      Scroll.Add (Area);
      Paned.Pack1 (Scroll, True, False);

      --  Side panel
      Gtk_New_Vbox (Panel, False, 6);
      Panel.Set_Border_Width (6);
      Panel.Set_Size_Request (330, -1);
      Paned.Pack2 (Panel, False, False);

      Gtk_New (Status_Label);
      Status_Label.Set_Alignment (0.0, 0.0);
      Status_Label.Set_Line_Wrap (True);
      Panel.Pack_Start (Status_Label, False, False, 0);

      Gtk_New (Mini);
      Mini.Set_Size_Request (-1, 130);
      Mini.Add_Events (Button_Press_Mask or Button1_Motion_Mask);
      Mini.On_Draw (Mini_Draw'Access);
      Mini.On_Button_Press_Event (Mini_Press'Access);
      Mini.On_Motion_Notify_Event (Mini_Motion'Access);
      Panel.Pack_Start (Mini, False, False, 0);
      Scroll.Get_Hadjustment.On_Value_Changed (Scrolled'Access);
      Scroll.Get_Vadjustment.On_Value_Changed (Scrolled'Access);

      Gtk_New (Frame, "Selected unit");
      Gtk_New (Unit_Label);
      Unit_Label.Set_Alignment (0.0, 0.0);
      Unit_Label.Set_Line_Wrap (True);
      Unit_Label.Set_Size_Request (-1, 160);
      Frame.Add (Unit_Label);
      Panel.Pack_Start (Frame, False, False, 0);

      Gtk_New_Hbox (Buttons, True, 4);
      Gtk_New (Btn_Resupply, "Resupply");
      Btn_Resupply.On_Clicked (On_Resupply'Access);
      Gtk_New (Btn_Reinforce, "Reinforce");
      Btn_Reinforce.On_Clicked (On_Reinforce'Access);
      Gtk_New (Btn_Buy, "Buy unit");
      Btn_Buy.On_Clicked (On_Buy'Access);
      Buttons.Pack_Start (Btn_Resupply);
      Buttons.Pack_Start (Btn_Reinforce);
      Buttons.Pack_Start (Btn_Buy);
      Panel.Pack_Start (Buttons, False, False, 0);

      Gtk_New_Hbox (Buttons, True, 4);
      Gtk_New (Btn_Undo, "Undo move");
      Btn_Undo.On_Clicked (On_Undo'Access);
      Gtk_New (Btn_Next, "Next unit");
      Btn_Next.On_Clicked (On_Next'Access);
      Gtk_New (Btn_End, "End turn");
      Btn_End.On_Clicked (On_End'Access);
      Buttons.Pack_Start (Btn_Undo);
      Buttons.Pack_Start (Btn_Next);
      Buttons.Pack_Start (Btn_End);
      Panel.Pack_Start (Buttons, False, False, 0);

      Gtk_New (Frame, "Terrain / target");
      Gtk_New (Info_Label);
      Info_Label.Set_Alignment (0.0, 0.0);
      Info_Label.Set_Line_Wrap (True);
      Info_Label.Set_Size_Request (-1, 150);
      Frame.Add (Info_Label);
      Panel.Pack_Start (Frame, False, False, 0);

      Gtk_New (Log_Buffer);
      Gtk_New (Log_View, Log_Buffer);
      Log_View.Set_Editable (False);
      Log_View.Set_Cursor_Visible (False);
      Log_View.Set_Wrap_Mode (Wrap_Word);
      Log_Buffer.Get_End_Iter (Iter);
      Log_End := Log_Buffer.Create_Mark ("end", Iter, False);
      Gtk_New (Log_Scroll);
      Log_Scroll.Set_Policy (Policy_Automatic, Policy_Automatic);
      Log_Scroll.Add (Log_View);
      Gtk_New (Frame, "Combat log");
      Frame.Add (Log_Scroll);
      Panel.Pack_Start (Frame, True, True, 0);

      Anim.On_Redraw := Anim_Redraw'Access;
      Anim.On_Done   := Anim_Finished'Access;
      Anim.On_Focus  := Ensure_Visible'Access;
      Update_Panels;
      Win.Show_All;
      Id := Glib.Main.Idle_Add (Startup'Access);
   end Create;

end Game_Window;
