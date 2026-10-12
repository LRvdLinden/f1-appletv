from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, sys
RED=(237,28,36); WHITE=(255,255,255)
FONT="/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
try:
    import glob
    cand=glob.glob("/usr/share/fonts/truetype/google-fonts/Poppins-ExtraBold*")+glob.glob("/usr/share/fonts/truetype/google-fonts/Poppins-Black*")
    if cand: FONT=cand[0]
except: pass

def background(w,h):
    img=Image.new("RGB",(w,h))
    d=ImageDraw.Draw(img)
    for y in range(h):
        t=y/h
        c=(int(22-10*t),int(22-10*t),int(28-12*t))
        d.line([(0,y),(w,y)],fill=c)
    # subtle diagonal carbon lines
    ov=Image.new("RGBA",(w,h),(0,0,0,0)); od=ImageDraw.Draw(ov)
    step=max(6,w//110)
    for x in range(-h,w,step):
        od.line([(x,0),(x+h,h)],fill=(255,255,255,7),width=max(1,step//3))
    img=Image.alpha_composite(img.convert("RGBA"),ov)
    return img

def draw_kerb(img):
    w,h=img.size
    d2=ImageDraw.Draw(img)
    kh=int(min(w,h)*0.06)
    seg=max(4,int(min(w,h)*0.085))
    y0=h-kh
    x=-seg*2;i=0
    while x<w:
        d2.polygon([(x,y0+kh),(x+seg,y0+kh),(x+seg+kh*0.6,y0),(x+kh*0.6,y0)],fill=RED if i%2==0 else WHITE)
        x+=seg;i+=1
    return img

def mark(w,h,scale=1.0,with_bg=True):
    img=background(w,h) if with_bg else Image.new("RGBA",(w,h),(0,0,0,0))
    layer=Image.new("RGBA",(w*2,h*2),(0,0,0,0))
    d=ImageDraw.Draw(layer)
    s=min(w,h)*2*scale
    cx,cy=w*1.0-0.02*s,h*0.94
    # speed stripes
    for i,(off,length,col) in enumerate([(-0.20,0.42,RED),(-0.06,0.34,RED),(0.08,0.26,WHITE)]):
        y=cy+off*s
        x1=cx-0.46*s; x2=x1+length*s
        d.rounded_rectangle([x1,y-0.045*s,x2,y+0.045*s],radius=0.045*s,fill=col)
    # P letter
    font=ImageFont.truetype(FONT,int(0.78*s))
    bbox=d.textbbox((0,0),"P",font=font)
    tw=bbox[2]-bbox[0]; th=bbox[3]-bbox[1]
    d.text((cx-0.02*s-bbox[0], cy-th/2-bbox[1]-0.02*s),"P",font=font,fill=WHITE)
    # skew (italic) transform
    k=0.22
    layer=layer.transform(layer.size,Image.AFFINE,(1,k,-k*h,0,1,0),resample=Image.BICUBIC)
    layer=layer.resize((w,h),Image.LANCZOS)
    img=Image.alpha_composite(img.convert("RGBA"),layer)
    if with_bg:
        draw_kerb(img)
    return img

