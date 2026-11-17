--  A simple computer opponent. Acts one unit per Step so the UI can
--  show the moves as they happen.
package Engine.AI is
   procedure Begin_Turn;
   --  Returns False when the side has nothing more to do.
   function Step return Boolean;
end Engine.AI;
