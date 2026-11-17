--  Fire-and-forget sound effects via the system's command line player
--  (paplay, pw-play or aplay). Silently does nothing if none exists.
package Sound is
   Enabled : Boolean := True;
   procedure Play (Name : String);   --  data/sounds/<Name>.wav
end Sound;
