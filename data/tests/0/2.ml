let f (x1 : int list) =
    map (fun x2 -> x2 - 1) x1
in
assert ((equal (-1 :: 0 :: []) (f (0 :: 1 :: []))) && (equal (-2 :: 0 :: []) (f (-1 :: 1 :: []))))
