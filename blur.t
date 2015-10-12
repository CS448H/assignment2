local I = require("img")
local image,concreteimage = I.image,I.concreteimage

local function doblur(a)
    local blur_x = (a:shift(-1,0) + a + a:shift(1,0))*(1.0/3.0)
    local blur_y = (blur_x:shift(0,-1) + blur_x + blur_x:shift(0,1))*(1.0/3.0) 
    return blur_y
end
local r = (doblur(image.input(0)))


local method,ifile,ofile = unpack(arg)
local inputimage = concreteimage.load(ifile)
local result = r:run(method,inputimage)
local b = terralib.currenttimeinseconds()
local times = 100
for i = 1,times do
    local result = r:run(method,inputimage)
end
local e = terralib.currenttimeinseconds()
print(times*result.width*result.height/1e6 / (e - b), "MP/s")
result:save(ofile)

