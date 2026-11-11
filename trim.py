p='modules/ui_core/root.zig'
s=open(p).read()
s=s.rstrip('\n')+'\n'
open(p,'w').write(s)
print('done')
