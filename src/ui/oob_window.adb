with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Glib;                   use Glib;
with Gdk.Event;
with Gtk.Widget;             use Gtk.Widget;
with Gtk.Box;                use Gtk.Box;
with Gtk.Label;              use Gtk.Label;
with Gtk.List_Store;         use Gtk.List_Store;
with Gtk.Tree_Model;         use Gtk.Tree_Model;
with Gtk.Tree_View;          use Gtk.Tree_View;
with Gtk.Tree_View_Column;   use Gtk.Tree_View_Column;
with Gtk.Tree_Selection;     use Gtk.Tree_Selection;
with Gtk.Cell_Renderer_Text; use Gtk.Cell_Renderer_Text;
with Gtk.Scrolled_Window;    use Gtk.Scrolled_Window;
with Gtk.Enums;              use Gtk.Enums;
with Gtk.Window;             use Gtk.Window;
with Engine;                 use Engine;
with Engine.Hexes;           use Engine.Hexes;
with Engine.Units;           use Engine.Units;
with Engine.Game;            use Engine.Game;

package body Oob_Window is

   Win     : Gtk_Window;
   Store   : Gtk_List_Store;
   Tree    : Gtk_Tree_View;
   Summary : Gtk_Label;
   Side    : Player_Side := 1;
   Filling : Boolean := False;

   Col_Name   : constant := 0;
   Col_Str    : constant := 1;
   Col_Exp    : constant := 2;
   Col_Ammo   : constant := 3;
   Col_Fuel   : constant := 4;
   Col_Supply : constant := 5;
   Col_State  : constant := 6;
   Col_Where  : constant := 7;
   Col_Color  : constant := 8;
   Col_Index  : constant := 9;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Img;

   function Is_Open return Boolean is
     (Win /= null and then Win.Get_Visible);

   function Place_Of (H : Hex) return String is
      Best   : Unbounded_String;
      Best_D : Natural := 3;
   begin
      --  Name the nearest named place within two hexes, if any.
      for C in H.Col - 2 .. H.Col + 2 loop
         for R in H.Row - 3 .. H.Row + 3 loop
            if In_Map ((C, R))
              and then Length (G.Cells (C, R).Name) > 0
              and then Distance ((C, R), H) < Best_D
            then
               Best   := G.Cells (C, R).Name;
               Best_D := Distance ((C, R), H);
            end if;
         end loop;
      end loop;
      if Length (Best) = 0 then
         return Image (H);
      elsif Best_D = 0 then
         return To_String (Best);
      end if;
      return "near " & To_String (Best);
   end Place_Of;

   procedure Update (S : Side_Id) is
      Iter   : Gtk_Tree_Iter;
      Count  : Natural := 0;
      Ready  : Natural := 0;
      Cut    : Natural := 0;
      Total  : Natural := 0;
   begin
      if not Is_Open or else not G.Loaded then
         return;
      end if;
      if S in Player_Side then
         Side := S;
      end if;
      Filling := True;
      Store.Clear;
      for Pass in Boolean loop        --  ground units first, then aircraft
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            declare
               U : constant Unit := G.Units (I);
               T : constant Unit_Type := G.Types (U.Kind);
               L : Supply_Level;
            begin
               if U.Alive and then U.Side = Side and then Is_Air (T) = Pass
               then
                  L := Supply_Of (I);
                  Count := Count + 1;
                  Total := Total + U.Strength;
                  Store.Append (Iter);
                  Store.Set (Iter, Col_Name,
                             To_String (T.Name)
                             & (if U.Core then " *" else ""));
                  Store.Set (Iter, Col_Str, Img (U.Strength));
                  Store.Set (Iter, Col_Exp,
                             (1 .. Exp_Level (U) => '*'));
                  Store.Set (Iter, Col_Ammo,
                             Img (U.Ammo) & "/" & Img (T.Max_Ammo));
                  Store.Set (Iter, Col_Fuel,
                             (if T.Max_Fuel > 0
                              then Img (U.Fuel) & "/" & Img (T.Max_Fuel)
                              else "-"));
                  Store.Set (Iter, Col_Supply,
                             (if Is_Surrounded (I) then "SURROUNDED"
                              else (case L is
                                       when Supplied   => "ok",
                                       when Low_Supply => "low",
                                       when Cut_Off    => "CUT OFF")));
                  Store.Set (Iter, Col_State,
                             (if U.Side /= G.Current then "-"
                              elsif U.Has_Attacked and then U.Moves_Left = 0
                              then "done"
                              elsif U.Has_Attacked then "attacked"
                              elsif U.Has_Moved then "moved"
                              else "ready"));
                  Store.Set (Iter, Col_Where, Place_Of (U.Pos));
                  Store.Set (Iter, Col_Color,
                             (if L = Cut_Off or else Is_Surrounded (I)
                              then "#c00000"
                              elsif L = Low_Supply then "#b07000"
                              elsif U.Strength <= 4 then "#a04000"
                              else "#000000"));
                  Store.Set (Iter, Col_Index, Gint (I));
                  if U.Side = G.Current and then not U.Has_Moved
                    and then not U.Has_Attacked
                  then
                     Ready := Ready + 1;
                  end if;
                  if L = Cut_Off then
                     Cut := Cut + 1;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      Filling := False;
      Win.Set_Title ("Order of battle - " & To_String (G.Sides (Side).Name));
      Summary.Set_Markup
        ("<b>" & To_String (G.Sides (Side).Name) & "</b>: " & Img (Count)
         & " units, total strength " & Img (Total)
         & (if Side = G.Current then ", " & Img (Ready) & " ready" else "")
         & (if Cut > 0 then ", <span foreground='#c00000'>" & Img (Cut)
            & " out of supply</span>" else "")
         & "   (* = core unit)");
   end Update;

   procedure Selection_Changed
     (Sel : access Gtk_Tree_Selection_Record'Class)
   is
      Model : Gtk_Tree_Model;
      Iter  : Gtk_Tree_Iter;
   begin
      if Filling or else On_Pick = null then
         return;
      end if;
      Sel.Get_Selected (Model, Iter);
      if Iter /= Null_Iter then
         On_Pick (Positive (Get_Int (Model, Iter, Col_Index)));
      end if;
   end Selection_Changed;

   function On_Delete
     (W : access Gtk_Widget_Record'Class;
      E : Gdk.Event.Gdk_Event) return Boolean
   is
      pragma Unreferenced (E);
   begin
      W.Hide;
      return True;
   end On_Delete;

   procedure Build (Parent : Gtk_Window) is
      Box    : Gtk_Box;
      Scroll : Gtk_Scrolled_Window;

      procedure Column (Title : String; Idx : Gint) is
         C : Gtk_Tree_View_Column;
         R : Gtk_Cell_Renderer_Text;
         N : Gint;
         pragma Unreferenced (N);
      begin
         Gtk_New (R);
         Gtk_New (C);
         C.Set_Title (Title);
         C.Pack_Start (R, True);
         C.Add_Attribute (R, "text", Idx);
         C.Add_Attribute (R, "foreground", Col_Color);
         C.Set_Resizable (True);
         C.Set_Sort_Column_Id (Idx);
         N := Tree.Append_Column (C);
      end Column;
   begin
      Gtk_New (Win);
      Win.Set_Transient_For (Parent);
      Win.Set_Default_Size (640, 420);
      Win.On_Delete_Event (On_Delete'Access);
      Gtk_New_Vbox (Box, False, 4);
      Box.Set_Border_Width (6);
      Win.Add (Box);
      Gtk_New (Summary);
      Summary.Set_Alignment (0.0, 0.5);
      Box.Pack_Start (Summary, False, False, 0);

      Gtk_New (Store, (Col_Name .. Col_Color => GType_String,
                       Col_Index => GType_Int));
      Gtk_New (Tree, +Store);
      Column ("Unit", Col_Name);
      Column ("Str", Col_Str);
      Column ("Exp", Col_Exp);
      Column ("Ammo", Col_Ammo);
      Column ("Fuel", Col_Fuel);
      Column ("Supply", Col_Supply);
      Column ("Status", Col_State);
      Column ("Location", Col_Where);
      Tree.Get_Selection.On_Changed (Selection_Changed'Access);

      Gtk_New (Scroll);
      Scroll.Set_Policy (Policy_Automatic, Policy_Automatic);
      Scroll.Add (Tree);
      Box.Pack_Start (Scroll, True, True, 0);
      declare
         Help : Gtk_Label;
      begin
         Gtk_New (Help, "Click a unit to select it on the map.");
         Help.Set_Alignment (0.0, 0.5);
         Box.Pack_Start (Help, False, False, 0);
      end;
   end Build;

   procedure Show (Parent : Gtk_Window; S : Player_Side) is
   begin
      if Win = null then
         Build (Parent);
      end if;
      Side := S;
      Win.Show_All;
      Win.Present;
      Update (S);
   end Show;

end Oob_Window;
