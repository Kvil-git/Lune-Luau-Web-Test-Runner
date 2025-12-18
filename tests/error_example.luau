local function Needs_To_Be_Tested(a: number, b: number)
    return a + b
end


return function()
    if Needs_To_Be_Tested(1, 1) ~= 2 then
        error("How can 1+1 ~= 2 bro are you ok")
    end
    return "Passed"
end