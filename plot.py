from numpy import *
import matplotlib.pyplot as plt, matplotlib
matplotlib.rc('text', usetex=True)

fig, plot = plt.subplots(1)

xs = [2,3, 4,5, 6,7,8]
ys = [30,29, 28,25, 22,20,19]
plt.plot(xs, ys, label='AWS M3')

plt.ylim(0,max(ys))
plt.ylabel(r'changes/second')
plt.xlabel(r'\# servers')
plt.savefig('aws.pgf')
# plt.savefig('aws.pdf')
