
import time
from machine import Pin
from neopixel import NeoPixel

pin = Pin(39, Pin.OUT)
np = NeoPixel(pin, 192)

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
    np[(n + 192 - 1) % 192] = (0,0,0)
    np[n] = (255,255,255)
    np.write()

while True:
    for n in range(0, 192):
        one_on(n)
        time.sleep(0.1)

