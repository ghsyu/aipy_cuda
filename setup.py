from distutils.core import setup, Extension
from distutils.command.build_ext import build_ext
from distutils.ccompiler import CCompiler
from distutils.errors import DistutilsExecError, CompileError
from distutils import log
import os, numpy, platform

NVCC, CUDA_DIR = '', ''
for path in ('/usr/local/cuda', '/opt/cuda'):
    if os.path.exists(path):
        CUDA_DIR = path
        NVCC = os.path.join(path, 'bin', 'nvcc')
        break
if CUDA_DIR == '': log.warn("No CUDA installation was found.  Trying anyway...")

class CudaCompiler(CCompiler):
    compiler_type = 'nvcc'
    compiler_so = [NVCC]
    executables = {'compiler' : [NVCC]}
    src_extensions = ['.cu']
    obj_extension = '.o'
    def _compile(self, obj, src, ext, cc_args, extra_postargs, pp_opts):
        try: self.spawn(self.compiler_so + cc_args + [src,'-o',obj] + extra_postargs)
        except DistutilsExecError, msg: raise CompileError, msg

class CudaExtension(Extension):
    def __init__(self, name, sources, **kwargs):
        Extension.__init__(self, name, sources, **kwargs)
        is64 = platform.architecture()[0].startswith('64')
        self.libraries.append('cudart')
        self.libraries.append('cufft')
        self.include_dirs.append(os.path.join(CUDA_DIR, 'include'))
        if is64 and os.path.exists(os.path.join(CUDA_DIR,'lib64')):
            self.library_dirs.append(os.path.join(CUDA_DIR,'lib64'))
        else: self.library_dirs.append(os.path.join(CUDA_DIR, 'lib'))
        try: self.cuda_sources = kwargs.pop('cuda_sources')
        except(KeyError): self.cuda_sources = []
        try: self.cuda_extra_compile_args = kwargs.pop('cuda_extra_compile_args')
        except(KeyError): self.cuda_extra_compile_args = []
        # NVCC wants us to call out 64/32-bit compiling explicitly
        if is64: self.cuda_extra_compile_args.append('-m64')
        else: self.cuda_extra_compile_args.append('-m32')
        self.cuda_extra_compile_args.append('-Xcompiler')
        self.cuda_extra_compile_args.append('-fPIC')
        # Extra args for debugging
        self.cuda_extra_compile_args.append('-g')
        self.cuda_extra_compile_args.append('-G')
        # Specifically for Fermi GPU
        self.cuda_extra_compile_args.append('-arch=compute_20')
        self.cuda_extra_compile_args.append('-code=sm_20')
        
class cuda_build_ext(build_ext):
    def build_extension(self, ext):
        if isinstance(ext, CudaExtension):
            log.info("pre-building '%s' CudaExtension using nvcc", ext.name)
            compiler = CudaCompiler()
            objects = compiler.compile(ext.cuda_sources, output_dir=self.build_temp,
                extra_postargs=ext.cuda_extra_compile_args)
            ext.extra_objects += objects
        build_ext.build_extension(self, ext)

setup(name = 'cuda_compress',
    description = 'Compress data using CUDA from Python',
    author = 'Gilbert Hsyu',
    version = '0.0.0',
    package_dir = {'cuda_compress':'src'},
    packages = ['cuda_compress'],
    ext_modules = [
        CudaExtension('cuda_compress._fft', ['src/_cuda_compress/wrap_fft.c'],
            cuda_sources = ['src/_aipy/vis_sim.cu'],
            include_dirs = ['src/_aipy', numpy.get_include()],),
        CudaExtension('aipy_cuda.adder', ['src/_aipy/cuda_add_wrap.c'],
            cuda_sources = ['src/_aipy/cuda_add.cu',],
            include_dirs = ['src/_aipy', numpy.get_include()],)
    ],
    cmdclass = {'build_ext': cuda_build_ext},
)

