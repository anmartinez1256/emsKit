"""stab.py EXPORT_DIR: exact leapfrog stability limit of an exported openEMS operator (OPENEMS_EXPORT_OPERATOR dir).
Builds P = diag(vi) C^T diag(iv) C (C = the engine's E->H curl bracket, vv=ii=1, lossless, boundary
tangential E as in the engine except the y/z/x=0 shift convention), symmetrised with sqrt(vi), and finds
lambda_max with Lanczos. Stable iff lambda_max <= 4, so dt_max = dt * 2/sqrt(lambda_max)."""
import json, os, sys
import numpy as np
from scipy.sparse.linalg import LinearOperator, eigsh

d = sys.argv[1]
h = json.load(open(os.path.join(d, "header.json")))
NX, NY, NZ = h["numLines"]; nv = h["numVectors"]; nops = h["numOps"]; dt = h["dT"]
idx = np.fromfile(os.path.join(d, "op_index.u32"), np.uint32).reshape(NX, NY, nv)
def table(name):
    t = np.fromfile(os.path.join(d, name + ".f32"), np.float32).reshape(3, nops, 4).astype(np.float64)
    # cell z = lane*nv + zv
    full = t[:, idx, :]                      # (3, NX, NY, nv, 4)
    full = np.transpose(full, (0, 1, 2, 4, 3)).reshape(3, NX, NY, 4 * nv)
    return full[..., :NZ]
vi, iv, vv, ii = table("vi"), table("iv"), table("vv"), table("ii")
print("vi<0:", int((vi < 0).sum()), "iv<0:", int((iv < 0).sum()), "vv range", vv.min(), vv.max(), "ii range", ii.min(), ii.max())
mask = np.zeros((NX, NY, NZ), bool); mask[:NX-1, :NY-1, :NZ-1] = True

def CV(V):
    """E -> H bracket (engine UpdateCurrents), zero outside x<NX-1, y<NY-1, z<NZ-1."""
    V0, V1, V2 = V
    b = np.zeros_like(V)
    s = (slice(0, NX-1), slice(0, NY-1), slice(0, NZ-1))
    b[0][s] = V2[:NX-1, :NY-1, :NZ-1] - V2[:NX-1, 1:NY, :NZ-1] - V1[:NX-1, :NY-1, :NZ-1] + V1[:NX-1, :NY-1, 1:NZ]
    b[1][s] = V0[:NX-1, :NY-1, :NZ-1] - V0[:NX-1, :NY-1, 1:NZ] - V2[:NX-1, :NY-1, :NZ-1] + V2[1:NX, :NY-1, :NZ-1]
    b[2][s] = V1[:NX-1, :NY-1, :NZ-1] - V1[1:NX, :NY-1, :NZ-1] - V0[:NX-1, :NY-1, :NZ-1] + V0[:NX-1, 1:NY, :NZ-1]
    return b

def CVT(I):
    """exact transpose of CV (I zero outside the mask)."""
    I0, I1, I2 = I * mask
    V = np.zeros_like(I)
    # b0 = V2[x,y,z] - V2[x,y+1,z] - V1[x,y,z] + V1[x,y,z+1]  (times I0)
    V[2] += I0; V[2][:, 1:, :] -= I0[:, :-1, :]; V[1] -= I0; V[1][:, :, 1:] += I0[:, :, :-1]
    # b1 = V0[x,y,z] - V0[x,y,z+1] - V2[x,y,z] + V2[x+1,y,z]
    V[0] += I1; V[0][:, :, 1:] -= I1[:, :, :-1]; V[2] -= I1; V[2][1:, :, :] += I1[:-1, :, :]
    # b2 = V1[x,y,z] - V1[x+1,y,z] - V0[x,y,z] + V0[x,y+1,z]
    V[1] += I2; V[1][1:, :, :] -= I2[:-1, :, :]; V[0] -= I2; V[0][:, 1:, :] += I2[:, :-1, :]
    return V

# adjoint check
rng = np.random.default_rng(1)
a = rng.standard_normal((3, NX, NY, NZ)); b = rng.standard_normal((3, NX, NY, NZ)) * mask
print("adjoint check", np.vdot(CV(a), b), np.vdot(a, CVT(b)))
S = np.sqrt(np.clip(vi, 0, None))
shape = (3, NX, NY, NZ); N = 3 * NX * NY * NZ
def mv(x):
    V = x.reshape(shape) * S
    return (S * CVT(iv * CV(V))).ravel()
A = LinearOperator((N, N), matvec=mv, dtype=np.float64)
lam = eigsh(A, k=3, which="LA", tol=1e-7, maxiter=5000, return_eigenvectors=True)
vals, vecs = lam
print("lambda_max (top 3):", vals)
lm = vals.max()
print(f"dt (Var3) = {dt:.6e} s, exact limit = {dt*2/np.sqrt(lm):.6e} s, ratio {2/np.sqrt(lm):.4f}")
v = vecs[:, np.argmax(vals)].reshape(shape) ** 2
k = np.unravel_index(np.argmax(v), shape)
print("mode peak at n,x,y,z =", k)
