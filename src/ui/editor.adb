with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada.Directories;
with Gtk.Widget;              use Gtk.Widget;
with Gtk.Box;                 use Gtk.Box;
with Gtk.Label;               use Gtk.Label;
with Gtk.Button;              use Gtk.Button;
with Gtk.Frame;               use Gtk.Frame;
with Gtk.GEntry;              use Gtk.GEntry;
with Gtk.Spin_Button;         use Gtk.Spin_Button;
with Gtk.Check_Button;        use Gtk.Check_Button;
with Gtk.Combo_Box;
with Gtk.Combo_Box_Text;      use Gtk.Combo_Box_Text;
with Gtk.Dialog;              use Gtk.Dialog;
with Gtk.Message_Dialog;      use Gtk.Message_Dialog;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter;         use Gtk.File_Filter;
with Gtk.Enums;               use Gtk.Enums;
with Gtk.Window;              use Gtk.Window;
with Gdk.Event;
with Engine;                  use Engine;
with Engine.Hexes;            use Engine.Hexes;
with Engine.Terrain;          use Engine.Terrain;
with Engine.Units;            use Engine.Units;
with Engine.Game;             use Engine.Game;
with Engine.Loader;
with Engine.Editing;
with Engine.Save;

package body Editor is

   Is_Active : Boolean := False;
   Parent_W  : Gtk_Window;
   Tools     : Gtk_Window;

   Mode_C, Terrain_C, Side_C, Type_C, Owner_C, Attacker_C : Gtk_Combo_Box_Text;
   Climate_C, Edge1_C, Edge2_C : Gtk_Combo_Box_Text;
   Name_E, Title_E, Desc_E, Side1_E, Side2_E : Gtk_Entry;
   Turns_S, Pres1_S, Pres2_S : Gtk_Spin_Button;
   Victory_B, Core_B, Fog_B : Gtk_Check_Button;
   Last_Path : Unbounded_String;

   type Tool_Mode is (Paint_Terrain, Place_Unit, Erase_Unit, Edit_Place);

   function Active return Boolean is (Is_Active);

   function Mode return Tool_Mode is
     (Tool_Mode'Val (Integer'Max (0, Integer (Mode_C.Get_Active))));

   function Help_Text return String is
   begin
      case Mode is
         when Paint_Terrain =>
            return "Paint terrain: left-click or drag to paint." & ASCII.LF
              & "Right-click picks up the terrain under the mouse.";
         when Place_Unit =>
            return "Place unit: left-click places the chosen unit" & ASCII.LF
              & "(aircraft go in the air slot). Right-click erases.";
         when Erase_Unit =>
            return "Erase: click or drag to remove units" & ASCII.LF
              & "(aircraft first, then the ground unit).";
         when Edit_Place =>
            return "Town / objective: left-click applies name, owner and"
              & ASCII.LF & "objective flag. Right-click reads them back.";
      end case;
   end Help_Text;

   procedure Message (Kind : Gtk_Message_Type; Text : String) is
      D : Gtk_Message_Dialog;
      R : Gtk_Response_Type;
      pragma Unreferenced (R);
   begin
      Gtk_New (D, Tools, Modal, Kind, Buttons_Ok, Text);
      R := D.Run;
      D.Destroy;
   end Message;

   procedure Changed is
   begin
      if On_Changed /= null then
         On_Changed.all;
      end if;
   end Changed;

   ------------------------------
   -- Widgets <-> game state   --
   ------------------------------

   procedure Fill_Types is
   begin
      Type_C.Remove_All;
      for T of G.Types loop
         Type_C.Append_Text (To_String (T.Name) & "  ("
                             & Class_Name (T.Class) & ")");
      end loop;
      Type_C.Set_Active (0);
   end Fill_Types;

   procedure Load_Settings is
   begin
      Title_E.Set_Text (To_String (G.Title));
      Desc_E.Set_Text (To_String (G.Description));
      Turns_S.Set_Value (Gdouble (G.Max_Turns));
      Attacker_C.Set_Active (Gint (G.Attacker) - 1);
      Side1_E.Set_Text (To_String (G.Sides (1).Name));
      Side2_E.Set_Text (To_String (G.Sides (2).Name));
      Pres1_S.Set_Value (Gdouble (G.Sides (1).Prestige));
      Pres2_S.Set_Value (Gdouble (G.Sides (2).Prestige));
      Fog_B.Set_Active (G.Fog);
      Climate_C.Set_Active (Gint (Climate_Kind'Pos (G.Climate)));
      Edge1_C.Set_Active (Gint (Edge_Kind'Pos (G.Supply_Edge (1))));
      Edge2_C.Set_Active (Gint (Edge_Kind'Pos (G.Supply_Edge (2))));
      Side_C.Remove_All;
      Side_C.Append_Text (To_String (G.Sides (1).Name));
      Side_C.Append_Text (To_String (G.Sides (2).Name));
      Side_C.Set_Active (0);
      Owner_C.Remove_All;
      Owner_C.Append_Text ("Nobody");
      Owner_C.Append_Text (To_String (G.Sides (1).Name));
      Owner_C.Append_Text (To_String (G.Sides (2).Name));
      Owner_C.Set_Active (0);
      Fill_Types;
   end Load_Settings;

   procedure Apply_Settings is
   begin
      G.Title := To_Unbounded_String (Title_E.Get_Text);
      G.Description := To_Unbounded_String (Desc_E.Get_Text);
      G.Max_Turns := Positive'Max (1, Integer (Turns_S.Get_Value_As_Int));
      G.Attacker := Player_Side (Integer'Max (0, Integer
                                   (Attacker_C.Get_Active)) + 1);
      G.Sides (1).Name := To_Unbounded_String (Side1_E.Get_Text);
      G.Sides (2).Name := To_Unbounded_String (Side2_E.Get_Text);
      G.Sides (1).Prestige := Integer (Pres1_S.Get_Value_As_Int);
      G.Sides (2).Prestige := Integer (Pres2_S.Get_Value_As_Int);
      G.Fog := Fog_B.Get_Active;
      G.Climate := Climate_Kind'Val
        (Integer'Max (0, Integer (Climate_C.Get_Active)));
      G.Supply_Edge (1) := Edge_Kind'Val
        (Integer'Max (0, Integer (Edge1_C.Get_Active)));
      G.Supply_Edge (2) := Edge_Kind'Val
        (Integer'Max (0, Integer (Edge2_C.Get_Active)));
      G.Winner := 0;
      G.Turn := 1;
      G.Current := G.First;
   end Apply_Settings;

   -------------------
   -- Map interaction --
   -------------------

   procedure Apply_Tool (H : Hex; Button : Guint) is
   begin
      if not In_Map (H) then
         return;
      end if;
      case Mode is
         when Paint_Terrain =>
            if Button = 3 then
               Terrain_C.Set_Active
                 (Gint (Terrain_Kind'Pos (Terrain_At (H))));
            else
               Engine.Editing.Paint
                 (H, Terrain_Kind'Val (Integer'Max
                                         (0, Integer (Terrain_C.Get_Active))));
            end if;
         when Place_Unit =>
            if Button = 3 then
               Engine.Editing.Erase (H);
            elsif Type_C.Get_Active >= 0 then
               declare
                  T : constant Type_Index :=
                    Natural (Type_C.Get_Active) + 1;
               begin
                  Engine.Editing.Put_Unit
                    (H, Player_Side (Integer'Max
                                       (0, Integer (Side_C.Get_Active)) + 1),
                     T);
                  if not G.Units.Is_Empty then
                     G.Units (G.Units.Last_Index).Core := Core_B.Get_Active;
                  end if;
               end;
            end if;
         when Erase_Unit =>
            Engine.Editing.Erase (H);
         when Edit_Place =>
            if Button = 3 then
               declare
                  C : constant Cell := G.Cells (H.Col, H.Row);
               begin
                  Name_E.Set_Text (To_String (C.Name));
                  Owner_C.Set_Active (Gint (C.Owner));
                  Victory_B.Set_Active (C.Victory);
               end;
            else
               Engine.Editing.Set_Place
                 (H, Name_E.Get_Text,
                  Side_Id (Integer'Max (0, Integer (Owner_C.Get_Active))),
                  Victory_B.Get_Active);
            end if;
      end case;
      Changed;
   end Apply_Tool;

   procedure Click (H : Hex; Button : Guint) is
   begin
      Apply_Tool (H, Button);
   end Click;

   procedure Drag (H : Hex) is
   begin
      if Mode in Paint_Terrain | Erase_Unit then
         Apply_Tool (H, 1);
      end if;
   end Drag;

   -------------
   -- Buttons --
   -------------

   function Ask_File (Saving : Boolean) return String is
      Dlg    : Gtk_File_Chooser_Dialog;
      Filter : Gtk_File_Filter;
      Dummy  : Gtk_Widget;
      Ok     : Boolean;
      pragma Unreferenced (Ok);
   begin
      Gtk_New (Dlg, (if Saving then "Save scenario" else "Open scenario"),
               Tools,
               (if Saving then Gtk.File_Chooser.Action_Save
                else Gtk.File_Chooser.Action_Open));
      Ok := Dlg.Set_Current_Folder
        (Ada.Directories.Full_Name (Engine.Loader.Data_Dir & "/scenarios"));
      Gtk_New (Filter);
      Filter.Set_Name ("Hexfront scenarios");
      Filter.Add_Pattern ("*.scn");
      Dlg.Add_Filter (Filter);
      if Saving then
         Dlg.Set_Do_Overwrite_Confirmation (True);
         Dlg.Set_Current_Name
           (if Length (Last_Path) > 0
            then Ada.Directories.Simple_Name (To_String (Last_Path))
            else "my_scenario.scn");
      end if;
      Dummy := Dlg.Add_Button ("Cancel", Gtk_Response_Cancel);
      Dummy := Dlg.Add_Button ((if Saving then "Save" else "Open"),
                               Gtk_Response_Accept);
      if Dlg.Run = Gtk_Response_Accept then
         declare
            F : constant String := Dlg.Get_Filename;
         begin
            Dlg.Destroy;
            if Saving and then Ada.Directories.Extension (F) /= "scn" then
               return F & ".scn";
            end if;
            return F;
         end;
      end if;
      Dlg.Destroy;
      return "";
   end Ask_File;

   procedure On_New (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
      Dlg   : Gtk_Dialog;
      Era_C : Gtk_Combo_Box_Text;
      Cols, Rows : Gtk_Spin_Button;
      Lbl   : Gtk_Label;
      Dummy : Gtk_Widget;
      Eras  : constant Engine.Editing.Name_Vectors.Vector :=
        Engine.Editing.List_Eras;
   begin
      Gtk_New (Dlg, "New map", Tools, Modal);
      Dlg.Get_Content_Area.Set_Spacing (6);
      Dlg.Get_Content_Area.Set_Border_Width (10);
      Gtk_New (Lbl, "Era");
      Dlg.Get_Content_Area.Pack_Start (Lbl, False, False, 0);
      Gtk_New (Era_C);
      for E of Eras loop
         Era_C.Append_Text (E);
      end loop;
      Era_C.Set_Active (0);
      Dlg.Get_Content_Area.Pack_Start (Era_C, False, False, 0);
      Gtk_New (Lbl, "Columns x rows");
      Dlg.Get_Content_Area.Pack_Start (Lbl, False, False, 0);
      Gtk_New (Cols, 6.0, Gdouble (Max_Cols), 1.0);
      Cols.Set_Value (24.0);
      Gtk_New (Rows, 6.0, Gdouble (Max_Rows), 1.0);
      Rows.Set_Value (14.0);
      Dlg.Get_Content_Area.Pack_Start (Cols, False, False, 0);
      Dlg.Get_Content_Area.Pack_Start (Rows, False, False, 0);
      Dummy := Dlg.Add_Button ("Cancel", Gtk_Response_Cancel);
      Dummy := Dlg.Add_Button ("Create", Gtk_Response_Accept);
      Dlg.Show_All;
      if Dlg.Run = Gtk_Response_Accept and then Era_C.Get_Active >= 0 then
         Engine.Editing.New_Map
           (Eras (Natural (Era_C.Get_Active) + 1),
            Positive (Cols.Get_Value_As_Int),
            Positive (Rows.Get_Value_As_Int));
         Last_Path := Null_Unbounded_String;
         Load_Settings;
         Changed;
      end if;
      Dlg.Destroy;
   exception
      when E : others =>
         Dlg.Destroy;
         Message (Message_Error, Ada.Exceptions.Exception_Message (E));
   end On_New;

   procedure Open_File (Path : String) is
   begin
      Engine.Loader.Load_Scenario (Path, Start => False);
      Last_Path := To_Unbounded_String (Path);
      Load_Settings;
      Changed;
   end Open_File;

   procedure On_Open (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
      F : constant String := Ask_File (Saving => False);
   begin
      if F /= "" then
         Open_File (F);
      end if;
   exception
      when E : others =>
         Message (Message_Error, "Cannot open: "
                  & Ada.Exceptions.Exception_Message (E));
   end On_Open;

   procedure On_Save (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Apply_Settings;
      declare
         Problem : constant String := Engine.Editing.Validate;
         F       : Unbounded_String;
      begin
         if Problem /= "" then
            Message (Message_Warning, "Saving anyway, but note: " & Problem);
         end if;
         F := To_Unbounded_String (Ask_File (Saving => True));
         if Length (F) > 0 then
            Engine.Editing.Write_Scenario (To_String (F));
            Last_Path := F;
            G.Scenario_Path := F;
            Message (Message_Info, "Saved " & To_String (F) & ASCII.LF
                     & "It now appears in Game > New scenario.");
         end if;
      end;
   exception
      when E : others =>
         Message (Message_Error, "Save failed: "
                  & Ada.Exceptions.Exception_Message (E));
   end On_Save;

   procedure Close_Editor is
   begin
      Is_Active := False;
      Tools.Hide;
   end Close_Editor;

   procedure On_Play_Test (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Apply_Settings;
      declare
         Problem : constant String := Engine.Editing.Validate;
         Path    : constant String :=
           Engine.Save.Save_Dir & "/editor_test.scn";
      begin
         if Problem /= "" then
            Message (Message_Warning, "Cannot play-test yet: " & Problem);
            return;
         end if;
         Engine.Editing.Write_Scenario (Path);
         Close_Editor;
         if On_Test /= null then
            On_Test (Path);
         end if;
      end;
   exception
      when E : others =>
         Message (Message_Error, "Test failed: "
                  & Ada.Exceptions.Exception_Message (E));
   end On_Play_Test;

   procedure On_Done (B : access Gtk_Button_Record'Class) is
      pragma Unreferenced (B);
   begin
      Close_Editor;
      if On_Close /= null then
         On_Close.all;
      end if;
   end On_Done;

   function On_Delete (W : access Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event) return Boolean is
      pragma Unreferenced (W, Event);
   begin
      On_Done (null);
      return True;   --  keep the window, just hide it
   end On_Delete;

   procedure Mode_Changed
     (C : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class) is
      pragma Unreferenced (C);
   begin
      Changed;
   end Mode_Changed;

   ----------------
   -- Build      --
   ----------------

   procedure Build is
      Box, Row : Gtk_Box;
      Frame    : Gtk_Frame;
      Inner    : Gtk_Box;
      Btn      : Gtk_Button;
      Lbl      : Gtk_Label;

      procedure Labelled (Text : String; W : access Gtk_Widget_Record'Class)
      is
         H : Gtk_Box;
         L : Gtk_Label;
      begin
         Gtk_New_Hbox (H, False, 6);
         Gtk_New (L, Text);
         L.Set_Size_Request (90, -1);
         L.Set_Alignment (0.0, 0.5);
         H.Pack_Start (L, False, False, 0);
         H.Pack_Start (W, True, True, 0);
         Inner.Pack_Start (H, False, False, 0);
      end Labelled;

      procedure Button (Text : String; CB : Cb_Gtk_Button_Void) is
      begin
         Gtk_New (Btn, Text);
         Btn.On_Clicked (CB);
         Row.Pack_Start (Btn, True, True, 0);
      end Button;
   begin
      Gtk_New (Tools);
      Tools.Set_Title ("Scenario editor");
      Tools.Set_Transient_For (Parent_W);
      Tools.Set_Default_Size (340, -1);
      Tools.On_Delete_Event (On_Delete'Access);
      Gtk_New_Vbox (Box, False, 6);
      Box.Set_Border_Width (8);
      Tools.Add (Box);

      Gtk_New_Hbox (Row, True, 4);
      Button ("New map", On_New'Access);
      Button ("Open...", On_Open'Access);
      Button ("Save as...", On_Save'Access);
      Box.Pack_Start (Row, False, False, 0);

      --  Tool
      Gtk_New (Frame, "Tool");
      Gtk_New_Vbox (Inner, False, 4);
      Inner.Set_Border_Width (6);
      Frame.Add (Inner);
      Gtk_New (Mode_C);
      Mode_C.Append_Text ("Paint terrain");
      Mode_C.Append_Text ("Place unit");
      Mode_C.Append_Text ("Erase unit");
      Mode_C.Append_Text ("Town / objective");
      Mode_C.Set_Active (0);
      Mode_C.On_Changed (Mode_Changed'Access);
      Labelled ("Mode", Mode_C);
      Gtk_New (Terrain_C);
      for T in Terrain_Kind loop
         Terrain_C.Append_Text (Name (T));
      end loop;
      Terrain_C.Set_Active (0);
      Labelled ("Terrain", Terrain_C);
      Gtk_New (Side_C);
      Labelled ("Unit side", Side_C);
      Gtk_New (Type_C);
      Labelled ("Unit type", Type_C);
      Gtk_New (Core_B, "Core unit (carries over in campaigns)");
      Inner.Pack_Start (Core_B, False, False, 0);
      Gtk_New (Name_E);
      Labelled ("Place name", Name_E);
      Gtk_New (Owner_C);
      Labelled ("Owner", Owner_C);
      Gtk_New (Victory_B, "Objective (victory hex)");
      Inner.Pack_Start (Victory_B, False, False, 0);
      Box.Pack_Start (Frame, False, False, 0);

      --  Scenario settings
      Gtk_New (Frame, "Scenario");
      Gtk_New_Vbox (Inner, False, 4);
      Inner.Set_Border_Width (6);
      Frame.Add (Inner);
      Gtk_New (Title_E);
      Labelled ("Title", Title_E);
      Gtk_New (Desc_E);
      Labelled ("Briefing", Desc_E);
      Gtk_New (Turns_S, 1.0, 99.0, 1.0);
      Labelled ("Turns", Turns_S);
      Gtk_New (Side1_E);
      Labelled ("Side 1", Side1_E);
      Gtk_New (Pres1_S, 0.0, 5000.0, 10.0);
      Labelled ("Prestige 1", Pres1_S);
      Gtk_New (Side2_E);
      Labelled ("Side 2", Side2_E);
      Gtk_New (Pres2_S, 0.0, 5000.0, 10.0);
      Labelled ("Prestige 2", Pres2_S);
      Gtk_New (Attacker_C);
      Attacker_C.Append_Text ("Side 1");
      Attacker_C.Append_Text ("Side 2");
      Labelled ("Attacker", Attacker_C);
      Gtk_New (Climate_C);
      for C in Climate_Kind loop
         Climate_C.Append_Text (Climate_Name (C));
      end loop;
      Climate_C.Set_Tooltip_Text
        ("Weather is rolled every turn from the climate");
      Labelled ("Climate", Climate_C);
      Gtk_New (Edge1_C);
      Gtk_New (Edge2_C);
      for E in Edge_Kind loop
         Edge1_C.Append_Text (Edge_Name (E));
         Edge2_C.Append_Text (Edge_Name (E));
      end loop;
      Edge1_C.Set_Tooltip_Text
        ("Map edge side 1 draws supply from (auto = behind its units)");
      Edge2_C.Set_Tooltip_Text
        ("Map edge side 2 draws supply from (auto = behind its units)");
      Labelled ("Supply edge 1", Edge1_C);
      Labelled ("Supply edge 2", Edge2_C);
      Gtk_New (Fog_B, "Fog of war");
      Inner.Pack_Start (Fog_B, False, False, 0);
      Box.Pack_Start (Frame, False, False, 0);

      Gtk_New (Lbl);
      Lbl.Set_Markup ("<small>The attacker must take every objective "
                      & "before the turn limit.</small>");
      Lbl.Set_Line_Wrap (True);
      Box.Pack_Start (Lbl, False, False, 0);

      Gtk_New_Hbox (Row, True, 4);
      Button ("Play-test", On_Play_Test'Access);
      Button ("Close editor", On_Done'Access);
      Box.Pack_Start (Row, False, False, 0);
   end Build;

   procedure Open (Parent : Gtk.Window.Gtk_Window) is
   begin
      if Tools = null then
         Parent_W := Parent;
         Build;
      end if;
      Is_Active := True;
      --  Start from the scenario being played (as authored), or a
      --  fresh map.
      if G.Loaded and then Length (G.Scenario_Path) > 0
        and then Ada.Directories.Exists (To_String (G.Scenario_Path))
      then
         Open_File (To_String (G.Scenario_Path));
      else
         Engine.Editing.New_Map ("ww2", 24, 14);
         Load_Settings;
      end if;
      Tools.Show_All;
      Changed;
   exception
      when others =>
         Engine.Editing.New_Map ("ww2", 24, 14);
         Load_Settings;
         Tools.Show_All;
         Changed;
   end Open;

end Editor;
