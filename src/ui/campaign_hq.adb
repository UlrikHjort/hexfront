-- ***************************************************************************
--                    Hexfront - Campaign_HQ
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

with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Glib;                   use Glib;
with Gtk.Widget;             use Gtk.Widget;
with Gtk.Dialog;             use Gtk.Dialog;
with Gtk.Label;              use Gtk.Label;
with Gtk.Button;             use Gtk.Button;
with Gtk.Box;                use Gtk.Box;
with Gtk.Combo_Box;
with Gtk.Combo_Box_Text;     use Gtk.Combo_Box_Text;
with Engine.Units;           use Engine.Units;
with Engine.Game;            use Engine.Game;
with Engine.Campaign;        use Engine.Campaign;

package body Campaign_HQ is

   CS : Campaign_State renames Engine.Campaign.C;

   Head    : Gtk_Label;
   Units_C : Gtk_Combo_Box_Text;
   Up_C    : Gtk_Combo_Box_Text;
   Up_Btn  : Gtk_Button;
   Options : array (1 .. 64) of Natural;
   N_Opt   : Natural := 0;
   Filling : Boolean := False;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Img;

   function Unit_Line (K : Positive) return String is
      T : constant Natural := Find_Type (To_String (CS.Carried (K).Type_Id));
      E : constant Natural := CS.Carried (K).Experience;
   begin
      return (if T = 0 then To_String (CS.Carried (K).Type_Id)
              else To_String (G.Types (T).Name))
        & "   exp " & Img (E) & " (" & Img (Natural'Min (E / 100, 5))
        & " stars)";
   end Unit_Line;

   procedure Fill_Options is
      K : constant Gint := Units_C.Get_Active;
   begin
      Up_C.Remove_All;
      N_Opt := 0;
      if K >= 0 then
         for T in G.Types.First_Index .. G.Types.Last_Index loop
            declare
               From : constant Natural :=
                 Find_Type (To_String (CS.Carried (Positive (K + 1)).Type_Id));
            begin
               if From /= 0 and then T /= From
                 and then G.Types (T).Class = G.Types (From).Class
                 and then Is_Air (G.Types (T)) = Is_Air (G.Types (From))
                 and then G.Types (T).Buyable and then N_Opt < Options'Last
               then
                  N_Opt := N_Opt + 1;
                  Options (N_Opt) := T;
                  Up_C.Append_Text
                    (To_String (G.Types (T).Name) & "  - cost "
                     & Img (Upgrade_Cost (Positive (K + 1), T))
                     & "   (attack " & Img (G.Types (T).Soft_Attack) & "/"
                     & Img (G.Types (T).Hard_Attack) & ", defence "
                     & Img (G.Types (T).Defense) & ")");
               end if;
            end;
         end loop;
      end if;
      if N_Opt > 0 then
         Up_C.Set_Active (0);
      end if;
      Up_Btn.Set_Sensitive (N_Opt > 0);
   end Fill_Options;

   procedure Fill_Units (Keep : Gint) is
   begin
      Filling := True;
      Units_C.Remove_All;
      for K in 1 .. Natural (CS.Carried.Length) loop
         Units_C.Append_Text (Img (K) & ". " & Unit_Line (K));
      end loop;
      Filling := False;
      if not CS.Carried.Is_Empty then
         Units_C.Set_Active
           (Gint'Min (Keep, Gint (CS.Carried.Length) - 1));
      end if;
      Head.Set_Markup
        ("<b>Campaign headquarters</b>" & ASCII.LF
         & "Your " & Img (Natural (CS.Carried.Length))
         & " surviving core units are refitted to full strength for the "
         & "next battle. You may re-equip units with better models of the "
         & "same kind; they keep their experience." & ASCII.LF & ASCII.LF
         & "Prestige available: <b>" & Img (CS.Prestige) & "</b>");
      Fill_Options;
   end Fill_Units;

   procedure Unit_Changed
     (W : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      pragma Unreferenced (W);
   begin
      if not Filling then
         Fill_Options;
      end if;
   end Unit_Changed;

   procedure On_Upgrade (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
      K : constant Gint := Units_C.Get_Active;
      O : constant Gint := Up_C.Get_Active;
   begin
      if K < 0 or else O < 0 then
         return;
      end if;
      declare
         T : constant Positive := Options (Natural (O) + 1);
      begin
         if Can_Upgrade (Positive (K + 1), T) then
            Upgrade (Positive (K + 1), T);
         else
            Head.Set_Markup ("<b>Not enough prestige for that.</b>"
                             & ASCII.LF & "Prestige available: "
                             & Img (CS.Prestige));
            return;
         end if;
      end;
      Fill_Units (K);
   end On_Upgrade;

   procedure Run (Parent : Gtk.Window.Gtk_Window) is
      Dlg   : Gtk_Dialog;
      Row   : Gtk_Box;
      Dummy : Gtk_Widget;
      Resp  : Gtk_Response_Type;
      pragma Unreferenced (Resp);
   begin
      if CS.Carried.Is_Empty then
         return;
      end if;
      Gtk_New (Dlg, "Campaign HQ", Parent, Modal);
      Dlg.Set_Default_Size (560, 260);
      Dlg.Get_Content_Area.Set_Spacing (8);
      Dlg.Get_Content_Area.Set_Border_Width (10);
      Gtk_New (Head);
      Head.Set_Line_Wrap (True);
      Head.Set_Max_Width_Chars (70);
      Head.Set_Alignment (0.0, 0.0);
      Dlg.Get_Content_Area.Pack_Start (Head, False, False, 0);
      Gtk_New (Units_C);
      Units_C.On_Changed (Unit_Changed'Access);
      Dlg.Get_Content_Area.Pack_Start (Units_C, False, False, 0);
      Gtk_New_Hbox (Row, False, 6);
      Gtk_New (Up_C);
      Gtk_New (Up_Btn, "Upgrade");
      Up_Btn.On_Clicked (On_Upgrade'Access);
      Row.Pack_Start (Up_C, True, True, 0);
      Row.Pack_Start (Up_Btn, False, False, 0);
      Dlg.Get_Content_Area.Pack_Start (Row, False, False, 0);
      Dummy := Dlg.Add_Button ("To the next battle", Gtk_Response_Accept);
      Fill_Units (0);
      Dlg.Show_All;
      Resp := Dlg.Run;
      Dlg.Destroy;
   end Run;

end Campaign_HQ;
