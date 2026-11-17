--  Hexfront - a turn based hex wargame engine with WW2, WW1 and
--  Napoleonic scenarios. GtkAda front end.
with Gtk.Main;
with Game_Window;

procedure Hexfront is
begin
   Gtk.Main.Init;
   Game_Window.Create;
   Gtk.Main.Main;
end Hexfront;
