--  The scenario editor: a floating tool window; the map in the main
--  window is the canvas.
with Glib;           use Glib;
with Gtk.Window;
with Engine.Hexes;

package Editor is

   type Callback is access procedure;
   type Path_Callback is access procedure (Path : String);

   On_Changed : Callback;       --  map content or size changed
   On_Test    : Path_Callback;  --  play-test the given scenario file
   On_Close   : Callback;       --  editor closed

   function Active return Boolean;

   procedure Open (Parent : Gtk.Window.Gtk_Window);

   procedure Click (H : Engine.Hexes.Hex; Button : Guint);
   procedure Drag (H : Engine.Hexes.Hex);   --  mouse moved, button held

   function Help_Text return String;        --  for the side panel

end Editor;
