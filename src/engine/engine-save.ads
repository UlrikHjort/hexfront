--  Saving and restoring a game in progress (plain text).
package Engine.Save is
   Save_Error : exception;
   procedure Save_Game (Path : String);
   procedure Load_Game (Path : String);
   function Save_Dir return String;   --  created on demand
end Engine.Save;
