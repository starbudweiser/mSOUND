# Génère trois pistes d'icône plates (1024 px, squircle 824 px, sans effet) pour mSOUND.
import sys
def bars(heights, x0, w, gap, cy, fill, cuts=None):
    out=[]; x=x0
    for i,h in enumerate(heights):
        out.append(f'<rect x="{x}" y="{cy-h/2}" width="{w}" height="{h}" rx="{w/2}" fill="{fill(i) if callable(fill) else fill}"/>')
        x+=w+gap
    return ''.join(out)
def svg(bg, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><rect x="100" y="100" width="824" height="824" rx="185" fill="{bg}"/>{body}</svg>'
H=[120,230,360,260,440,300,200,330,150]      # onde en bâtons
w,gap=44,30; total=len(H)*w+(len(H)-1)*gap; x0=(1024-total)/2
A=svg('#14B8A6', bars(H,x0,w,gap,512,'#FFFFFF'))
# B : fond bleu nuit, onde bleue + curseur de coupe blanc
B=svg('#16213A', bars(H,x0,w,gap,512,lambda i:'#0A84FF' if i<4 else '#14B8A6')+f'<rect x="{x0+4*(w+gap)+w/2-5}" y="270" width="10" height="484" rx="5" fill="#FFFFFF"/>')
# C : fond bleu, onde blanche coupée en deux moitiés décalées (couper / séparer)
left=bars(H[:4],x0,w,gap,512,'#FFFFFF'); right=bars(H[4:],x0+4*(w+gap)+60,w,gap,512,'#FFFFFF')
C=svg('#0A84FF', left+right)
for n,s in (('a',A),('b',B),('c',C)): open(f'piste_{n}.svg','w').write(s)
