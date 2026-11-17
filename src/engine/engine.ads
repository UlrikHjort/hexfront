--  Hexfront: a turn based, hex based operational war game engine.
--  The engine is era-neutral; eras (WW2, WW1, Napoleonic ...) are
--  described by data files (unit types + rule tweaks) and scenarios.
package Engine is
   pragma Pure;

   type Side_Id is range 0 .. 2;          --  0 = neutral / nobody
   subtype Player_Side is Side_Id range 1 .. 2;

   function Other (S : Player_Side) return Player_Side is
     (if S = 1 then 2 else 1);
end Engine;
