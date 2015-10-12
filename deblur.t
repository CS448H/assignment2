local I = require("img")
local image,concreteimage,toimage = I.image,I.concreteimage,I.toimage

local method,ifile,ofile = unpack(arg)

-- This example implements Lucy–Richardson deconvolution
-- which can deblur an image if you know the kernel used to blur it

-- It first uses your library to generate a blurred image. 
-- Then applies the algorithm to deblur it.
-- It will save both 'blurred_<filename>.pbm' and 
-- 'restored_<filename>.pbm'

function convolve(a)
    return  1/3*(a:shift(-1,-1) + a + a:shift(1,1))
end

local fakeblur = convolve(image.input(0))

local inputimage = concreteimage.load(ifile)
local blurredimage = fakeblur:run(method,inputimage)
blurredimage:save("blurred-"..ofile)


local function deconvolve(K, observed, N)
    local latent_est = toimage(255/2)
    for i = 1,N do
        local est_conv = K(latent_est)
        local relative_blur = observed / est_conv
        local error_est = K(relative_blur)
        latent_est = latent_est*error_est
    end
    return latent_est
end


local r = deconvolve(convolve, image.input(0), 10)

local result = r:run(method,blurredimage)
local b = terralib.currenttimeinseconds()
local times = 100
for i = 1,times do
    local result = r:run(method,blurredimage)
end
local e = terralib.currenttimeinseconds()
print(times*result.width*result.height/1e6 / (e - b), "MP/s")
result:save("restored-"..ofile)

