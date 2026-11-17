import random, sys
def to_cube(c,r):
    x=c; z=r-(c-(c&1))//2; return (x,-x-z,z)
def from_cube(x,y,z):
    c=x; r=z+(x-(x&1))//2; return (c,r)
def cround(x,y,z):
    rx,ry,rz=round(x),round(y),round(z)
    dx,dy,dz=abs(rx-x),abs(ry-y),abs(rz-z)
    if dx>dy and dx>dz: rx=-ry-rz
    elif dy>dz: ry=-rx-rz
    else: rz=-rx-ry
    return rx,ry,rz
def line(a,b):
    A=to_cube(*a);B=to_cube(*b)
    n=max(abs(A[i]-B[i]) for i in range(3))
    out=[]
    for i in range(n+1):
        t=i/max(n,1)
        p=[A[k]+(B[k]-A[k])*t+1e-6*(k+1) for k in range(3)]
        out.append(from_cube(*cround(*p)))
    return out
class Map:
    def __init__(s,w,h,base='.'):
        s.w,s.h=w,h; s.g=[[base]*w for _ in range(h)]
    def set(s,c,r,ch):
        if 0<=c<s.w and 0<=r<s.h: s.g[r][c]=ch
    def get(s,c,r): return s.g[r][c]
    def path(s,pts,ch,keep=''):
        for a,b in zip(pts,pts[1:]):
            for c,r in line(a,b):
                if s.get(c,r) not in keep: s.set(c,r,ch)
    def scatter(s,c0,r0,c1,r1,ch,p,seed,only='.'):
        rnd=random.Random(seed)
        for r in range(r0,r1+1):
            for c in range(c0,c1+1):
                if 0<=c<s.w and 0<=r<s.h and s.g[r][c] in only and rnd.random()<p: s.g[r][c]=ch
    def rect(s,c0,r0,c1,r1,ch):
        for r in range(r0,r1+1):
            for c in range(c0,c1+1): s.set(c,r,ch)
    def dump(s):
        return "\n".join(" ".join(row) for row in s.g)
