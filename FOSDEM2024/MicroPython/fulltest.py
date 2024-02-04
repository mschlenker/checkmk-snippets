
import time
import random
from machine import Pin
from neopixel import NeoPixel

numpix = 192
hexes = 24

pin = Pin(39, Pin.OUT)
np = NeoPixel(pin, numpix)
colors = [
    (0,255,0),
    (192,192,0),
    (255,0,0),
    (0,255,0)
]

def all_red(np):
    for n in range(0, 12):
        np[n] = (255,0,0)
    np.write()

def all_green(np):
    for n in range(0, 12):
        np[n] = (0,255,0)
    np.write()
    
def all_yellow(np):
    for n in range(0, 12):
        np[n] = (192,192,0)
    np.write()
    
def cycle(np):
    all_off(np)
    for n in range(0, 60):
        np[n % 12] = (255,255,255)
        np[(n + 11) % 12] =  (0,0,0)
        np.write()
        time.sleep(0.5)
    
def all_off(np):
    for n in range(0, 12):
        np[n] = (0,0,0)
    np.write()
    
def one_on(n):
    np[(n + numpix - 1) % numpix] = (0,0,0)
    np[n] = (255,255,255)
    np.write()

def random_random():
    randhex = random.randint(0, hexes - 1)
    randcolor = random.randint(0, 3)
    for n in range(randhex * 8, randhex * 8 + 7):
        print(n)
        print(randcolor)
        print(colors[randcolor])
        np[n] = colors[randcolor]
    np.write()

def switch_color(hex, col):
    for n in range(hex * 8, hex * 8 + 7):
        np[n] = colors[col]
    np.write()
    
for n in range(0, numpix):
    print(n)
    one_on(n)
    time.sleep(0.1)
np[numpix - 1] = (0,0,0)
np.write()

while True:
    i = input()
    h = 0
    c = 0
    # try:
    toks = i.split()
    h = int(toks[0])
    c = int(toks[1])
    switch_color(h, c)
    #except:
    #print("Could not parse/switch line: " + i)
    

    

