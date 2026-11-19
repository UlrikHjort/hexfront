--  Order of battle: a list of one side's units with their state.
--  Selecting a row picks that unit on the map.
with Gtk.Window;
with Engine;

package Oob_Window is

   type Pick_Callback is access procedure (U : Positive);
   On_Pick : Pick_Callback;

   --  Open (or raise) the window for side S.
   procedure Show (Parent : Gtk.Window.Gtk_Window; S : Engine.Player_Side);

   --  Refill the list if the window is open (call after game changes).
   procedure Update (S : Engine.Side_Id);

   function Is_Open return Boolean;

end Oob_Window;
