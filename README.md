# Assignment 2: Implementing an Image Processing Language

In this assignment, you will implement a simple image processing language similar to the one we have been using as an example in the class. In the process, you will be responsible for designing the intermediate representations that the language will use to lower the code from a high level expression into Terra code using metaprogramming.

We have provided the front-end of the language, which describes what image operations should be done, handles the loading and saving of images, and includes few test programs that use the language. We have also made a few simplifications so that you can mostly focus on IR design. In particular, images will just be grayscale floating point arrays with values in the range 0 to 255. To simplify the handling of boundaries, we have also defined images to be toroidal. That is, pixel `(-1,0)` is equal to pixel `(W - 1,0)`. We provide the Terra function `load_data` which handles toroidal loading of image data.

The language you will implement is nearly the same as the one shown in class:

    local input = image.input(0)
    local blur_x = (input:shift(-1,0) + input + input:shift(1,0))*(1.0/3.0)
    local blur_y = (blur_x:shift(0,-1) + blur_x + blur_x:shift(0,1))*(1.0/3.0) 

It supports: 

  * math operations (`+`,`-`,`*` and `/`) on images
  * using constants like 3.0
  * reading from a list of input images (`image.input(0)`, `image.input(1)`, ...)
  * accessing the image using a small _constant_ offset (`input:shift(-1,0)`)
    
A difference from the example given in class is that input images are not tied to a specific file, but instead work on an abstract numbered list of inputs. This allows us to reuse the same code for images of different sizes. A separate type `concreteimage` actually handles the loading and saving of images. To run the algorithm you call the run method on an image, passing in concrete images that bind to each of the inputs:

    local real_input = concreteimage.load("giraffebw.pbm")
    -- real_input binds to image.input(0)
    local real_output = blur_y:run("image_wide",real_input) 
    real_output:save("giraffebw_blurred.pbm")
    
The string `"image_wide"` specifies which optimization strategy to use. You will implement three strategies `"recompute"`, `"image_wide"`, and `"blocked"` in  your assignment.
The return value of the run method is another concrete image that holds the output.

## 1. Implement an intermediate representation for the image language

The methods like `image:shift()` or `image:constant()` each have a line:

    result.tree = error("NYI - your IR goes here")
    
In part one you should fill in these lines with your own code that implements the IR.
Hint: this IR will look very similar to the one in [example-2.t](http://cs448h.stanford.edu/example-2.t). You may want to implement a function `print_ir()` that can output your IR in a nice way for debugging befor moving on to other parts.

## 2. Strategy: recompute

The first (and simplest) strategy for compiling your IR into Terra code uses a single loop over each pixel, computing the entire value for each pixel individually. For instance, for the blur code shown earlier, you might generate a Terra function that looks like this:

    terra recompute(W : int, H : int, output : &float, inputs : &&float) : {}
        for y  = 0,H do
            for x = 0,W do
                output[y * W + x] = 0.33 *(0.33*(load_data($W, $H, $inputs[0], x + -1, y + -1 ) + 
                                                 load_data($W, $H, $inputs[0], x , y + -1) + 
                                                 load_data($W, $H, $inputs[0], x + 1, y + -1 )) 
                                     
                                         + 0.33*(load_data($W, $H, $inputs[0], x + -1, y ) + 
                                                 load_data($W, $H, $inputs[0], x, y) + 
                                                 load_data($W, $H, $inputs[0], x + 1, y ))
                                     
                                         + 0.33*(load_data($W, $H, $inputs[0], x + -1, y + 1 ) + 
                                                 load_data($W, $H, $inputs[0], x , y + 1) + 
                                                 load_data($W, $H, $inputs[0], x + 1, y + 1 )) )
            end
        end
    end
    
Implement the function `compile_ir_recompute(tree)` that takes your IR node and returns a Terra function like the one above. Hint: again, this strategy is similar to the one in [example-2.t](example-2.t). We recommend that you try to implement it on your own first, and then refer to that example if you are getting stuck. Note that in this version on the function the width, height, and array of input image buffers are passed as arguments to the Terra function. `input[0]` corresponds to the image construct `image.input(0)` in the examples. For this stage, we recommend doing a single pass translation. You can take your IR from part 1 and translate it directly into Terra code.

Run this strategy on two of input examples, `blur.t` and `iterated-blur.t` and record the speed (MP/s) for the large image (`giraffebw.pbm`):

    $ terra blur.t recompute giraffebw.bpm giraffebw_blur_recompute.pbm
    
You should use the small test image `test.pbm` to check that you algorithm is actually producing the right result (we've provided some references to check against).

### Questions:

  * Give one example of a redundant computation that this example performs? Why does this happen?
  * What throughputs did you measure (MB/s) for each of the examples?
  
## 3. Strategy: image_wide

Now we will implement an `image_wide` strategy. Whereas `recompute` would always compute common values that are shared across different pixels in the output version, `image_wide` will make sure that any outputs that might be used across pixels are only computed once. To do so, it computes image-wide intermediate values for certain computations, such as the `blur_x` image. The `image_wide` approach would generate code similar to this pseudo-code for the blur example:

    var blur_x_temp = allocate_image(W,H)
    for each pixel (x,y):
      blur_x_temp(x,y) = .33*(input(x-1,y) + input(x,y) + input(x+1,y))
    for each pixel (x,y):
      output(x,y) =  .33*(blur_x_temp(x,y-1) + blur_x_temp(x,y) + blur_x_temp(x,y+1))
    free_image(blur_x_temp)
    
Note that we don't need to create image-wide temporaries for all computations (e.g., `input(x-1,y) + input(x,y)` is not stored in an image), but it would still compute the same result if we did introduce one. In this part you will need to first determine which computations need to be stored into temporaries. Then come up with an order for computing those temporaries and storing the results into the output image. To keep this simple, you can use a heuristic for choosing whether a temporary is needed: you should create a temporary if either a node is non-constant and the node is used more than once or it is used directly by a _shift_ operation.

Implement the function `compile_ir_image_wide(tree)`. For this part of the assignment, you might consider doing the compilation in multiple passes. For instance, you might want to first compute which nodes should be stored in temporaries and convert to a different IR that represents the loop that calculates each temporary separately. Then another pass will take the new IR and use it to generate the terra code that emits the loop for each temporary calculation.

Run your new `image_wide` code on all three test examples (`blur.t`,`iterated-blur.t`, and `deblur.t`), check it is correct, and answer these questions.

### Questions:

  * Is there a case where our heuristic will introduce a temporary that is not strictly necessary? 
  * How did you decompose this transformation into passes? Did you try any other approach before the one you finally used?
  * Do you need boundary checks when loading from temporaries? Why or why not?
  * What throughputs did you measure for the examples? How do they compare to the `recompute` method? In the iterated blur example, how do you expect the comparative performance of the two methods to change as you increase the number of blur iterations?
  

## 4. Strategy: blocked

Our last strategy blends the two approaches from above. We still want to calculate temporaries for re-used computations like `blur_x`, but instead of doing it on the entire image, we compute a small block of the output image at a time, computing block-sized temporaries as needed. This cuts down on the needed temporary storage, and increases cache locality of the loads between temporaries. Here is pseudo code for what this would look like for our blur example:

    for beginy = 0,H,BLOCKSIZE:
      for beginx = 0,W,BLOCKSIZE:
         var input_block : float[(BLOCKSIZE+2)*(BLOCKSIZE+2)]
         for each pixel (x,y) in input_block:
           input_block(x,y) = input(x,y)
         var blur_x : float[(BLOCKSIZE+1)*(BLOCKSIZE+1)]
         for each pixel (x,y) in blur_x:
           blur_x(x,y) = .33*(input_block(x-1,y) + input_block(x,y) + input_block(x+1,y))
         for each pixel (e,y) in output:
           output(x,y) = .33*(blur_x(x,y-1) + blur_x(x,y) + blur_x(x,y+1))
      end
    end 

A couple things to notice. First, there is an output loop over blocks, with the temporaries only existing inside a block. Second, the temporaries are basically the same as before, except for the fact that we load the input directly into a temporary. Finally, note that the size of the temporaries for `blur_x` and `input_block` are expanded, centered around the block of the output being computed. This is because later things in the pipeline access shifted pixels from earlier things and we must ensure we calculated enough of the temporary so those pixels are available. 

Implement the function `compile_ir_blocked(tree)`. Since the assignment of temporaries is similar to the previous section, you might consider re-using it across both functions. To correctly calculate the output, you will also need to calculate how much to expand each temporary block. This is a property of the shifted accesses and can be calculated as a pass over the IR. To keep indexing arithmetic simple, you can represent this expansion conservatively as a single integer `maxstencil` that indicates how much to expand the block of a temporary, keeping it square centered around the output block. You should also experiment with different block sizes to find one that works best.

Run, measure, and test your code. Use all three input examples.

#### Questions:

* Do you need boundary checks when loading from temporaries? Why or why not?
* What block size worked best for you? Why might it run slower if the block was smaller or bigger than that?
* With blocks having different sizes and starting locations in image space, representing indices can quickly become tricky. The block size also probably doesn't evenly divide the image. How did you design the indexing math to manage this complexity?
* What throughputs did you measure for the examples? How do they compare to previous examples? Is this what you expected? Why?
* If we keep increasing the number of iterations in the integrated blur example, is there a point at which you expect one strategy to win out over another? Explain.
* Unlike previous stages we loaded the input into a temporary block. Why is this a good/bad idea?

## 5. Writeup

In addition to answers to the questions posed in parts 2,3, and 4, we'd like you to write up a little bit about what you did and what you learned. Submit this writeup as a `writeup.md` in your submission repo along with answers to the questions.

## _n. Extra Credit_

If you want to do more, here are some ideas we will give extra credit for:

* Improve boundary handling: one source of overhead is the `load_data` function which has to handle when we are on an image boundary correct. Come up with a way to reduce the number of times boundaries need to be checked. What is your approach to boundaries and how much performance was gained?
* Multi-threading: use the `pthreads` library (see [pthreads.t](https://github.com/zdevito/terra/blob/master/tests/pthreads.t)) to multi-thread computation of the image. How much performance do you gain doing this?
* Vectorization: x86 machines have vector instructions (AVX or SSE). Change your code use these instructions by computing multiple pixels at once.  See [simplevec.t](https://github.com/zdevito/terra/blob/master/tests/simplevec.t) for an example of using vectors in Terra. By default, vector loads must be aligned to the size of the vector. If you need to use unaligned stores and loads you can use the code below. How much performance do you gain doing this? How did you handle boundary conditions 

Submit extra-credit as a separate `img.t` file, so that we can still test your standard version, and explain what you tried to do.

### Unaligned Load/Store code:

    local terra unalignedload(addr : &float)
        return terralib.attrload([&vector(float,4)](addr), { align = 4 })
    end
    local terra unalignedstore(addr : &float, value : vector(float,4))
        terralib.attrstore([&vector(float,4)](addr),value, { align = 4 })
    end
