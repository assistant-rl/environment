let f (x1 : int list) =
	map (fun x2 -> x2 * ?) x1
in
assert ((equal (0 :: -1 :: []) (f (0 :: -1 :: []))) && (equal (-2 :: 3 :: []) (f (-2 :: 3 :: []))))
