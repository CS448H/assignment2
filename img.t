local C = terralib.includecstring [[
    #include<stdio.h>
    #include<stdlib.h>
    #include<string.h>
]]
local function alloc_image_data(w,h)
    local data = C.malloc(4*w*h)
    return terralib.cast(&float,data)
end
local function loadpbm(filename)
    local F = assert(io.open(filename,"rb"),"file not found")
    local cur
    local function next()
        cur = F:read(1)
    end
    next()
    local function isspace()
        return cur and (cur:match("%s") or cur == "#")
    end
    local function isdigit()
        return cur and cur:match("%d")
    end
    local function parseWhitespace()
        assert(isspace(), "expected at least one whitespace character")
        while isspace() do 
            if cur == "#" then 
                repeat
                    next()
                until cur == "\n"
            end
            next() 
        end
    end 
    local function parseInteger()
        assert(isdigit(), "expected a number")
        local n = ""
        while isdigit() do
            n = n .. cur
            next()
        end
        return assert(tonumber(n),"not a number?")
    end
    assert(cur == "P", "wrong magic number")
    next()
    assert(cur == "6", "wrong magic number")
    next()
    
    local image = {}
    parseWhitespace()
    image.width = parseInteger()
    parseWhitespace()
    image.height = parseInteger()
    parseWhitespace()
    local precision = parseInteger()
    assert(precision == 255, "only supports 255 as max value")
    assert(isspace(), "expected whitespace after precision")
    local data_as_string = F:read(image.width*image.height*3)
    -- read the data as flat data
    local data = alloc_image_data(image.width,image.height)
    for i = 0,image.width*image.height - 1 do
        local r,g,b = data_as_string:byte(3*i+1,3*i+3)
        data[i] = math.min(255,(r+g+b)/3.0)
        local x,y = i % 16, math.floor(i / 16) 
    end
    image.data = data
    next()
    assert(cur == nil, "expected EOF")
    return image
end

local headerpattern = [[
P6
%d %d
%d
]]

local function savepbm(image,filename)
    local F = assert(io.open(filename,"wb"), "file could not be opened for writing")
    F:write(string.format(headerpattern, image.width, image.height, 255))
    local function writeNumber(v)
        assert(type(v) == "number","NaN?")
        F:write(string.char(v))
    end
    local floor,max,min,char,data,fwrite = math.floor,math.max,math.min,string.char,image.data,F.write
    for i = 0, image.width*image.height - 1 do
        local v = data[i]
        v = floor(v)
        v = max(0,min(v,255))
        v = char(v)
        fwrite(F,v..v..v)
    end
    F:close()
end

local function newclass(name)
    local cls = {}
    cls.__index = cls
    function cls.new(tbl)
        return setmetatable(tbl,cls)
    end
    function cls.isinstance(x) 
        return getmetatable(x) == cls 
    end
    function cls:__tostring()
        return "<"..name..">"
    end
    return cls
end

-- represents actual image data
local concreteimage = newclass("concreteimage")
function concreteimage.load(filename)
    return concreteimage.new(loadpbm(filename))
end
function concreteimage:save(filename)
    savepbm(self,filename)
end


-- represents an abstract computation that creates an image
local image  = newclass("image")
function image.constant(const)
    local result = image.new {}
    result.tree = error("NYI - your IR goes here")
    return result
end
function image.input(index)
    local result = image.new {}
    result.tree = error("NYI - your IR goes here")
    return result
end

-- Support constant numbers as images
local function toimage(x)
  if image.isinstance(x) then
    return x
  elseif type(x) == "number" then
    return image.constant(x)
  end
  return nil
end

local function pointwise(self,rhs,op)
    self,rhs = assert(toimage(self),"not an image"),assert(toimage(rhs),"not an image")
    local result = image.new {}
    result.tree = error("NYI - your IR goes here")
    return result
end

function image:__add(rhs)
    return pointwise(self,rhs,function(x,y) return `x + y end)
end
function image:__sub(rhs)
    return pointwise(self,rhs,function(x,y) return `x - y end)
end
function image:__mul(rhs)
    return pointwise(self,rhs,function(x,y) return `x * y end)
end
function image:__div(rhs)
    return pointwise(self,rhs,function(x,y) return `x / y end)
end
-- generate an image that translates the pixels in the new image 
function image:shift(sx,sy)
    local result = image.new {} 
    result.tree = error("NYI - your IR goes here")
    return result
end

local terra load_data(W : int, H : int, data : &float, x : int, y : int) : float
    while x < 0 do
        x = x + W
    end
    while x >= W do
        x = x - W
    end
    while y < 0 do
        y = y + H
    end
    while y >= H do
        y = y - H
    end
    return data[(y*W + x)]
end
local terra min(x : int, y : int)
    return terralib.select(x < y,x,y)
end
    
local function compile_ir_recompute(tree)
    -- YOUR CODE HERE
    local terra body(W : int, H : int, output : &float, inputs : &&float)
        for y = 0,H do
          for x = 0,W do
            output[(y*W + x)] = [ --[[YOUR CODE HERE]] 0 ]
          end
        end
    end
    return body
end

local function compile_ir_image_wide(tree)
    -- YOUR CODE HERE
end

local function compile_ir_blocked(tree)
    -- YOUR CODE HERE
end

function image:run(method,...)
    if not self[method] then
        local compile_ir        
        if "recompute" == method then
            compile_ir = compile_ir_recompute
        elseif "image_wide" == method then
            compile_ir = compile_ir_image_wide
        elseif "blocked" == method then
            compile_ir = compile_ir_blocked
        end
        assert(compile_ir,"unknown method "..tostring(method))
        self[method] = compile_ir(self.tree)
        assert(terralib.isfunction(self[method]),"compile did not return terra function")
        self[method]:compile()
        -- helpful for debug
         self[method]:printpretty(true,false)
        -- self[method]:disas()
    end
    local implementation = self[method]
    
    local width,height
    local imagedata = {}
    for i,im in ipairs({...}) do
        assert(concreteimage.isinstance(im),"expected a concrete image")
        width,height = width or im.width,height or im.height
        assert(width == im.width and height == im.height, "sizes of inputs do not match")
        imagedata[i] = im.data
    end
    assert(width and height, "there must be at least one input image")
    local inputs = terralib.new((&float)[#imagedata], imagedata) 
    local result = concreteimage.new { width = width, height = height }
    result.data = alloc_image_data(width,height)
    implementation(width,height,result.data,inputs)
    return result
end

return { image = image, concreteimage = concreteimage, toimage = toimage }