#ifndef _VIS_SIM_H_
#define _VIS_SIM_H_

#include <stdio.h>
#include <cuda.h>
#include <cuda_runtime_api.h>

#ifdef __cplusplus
extern "C" {
#endif

#define  CL_M_PI_F          3.14159274101257f

int vis_sim(float *, float *, float *, float *,
            float *, float *, float *, float *,
            int, int, int, float, float, float, float, float, float, 
            int, int);


static void HandleError( cudaError_t err,
                         const char *file,
                         int line ) {
    if (err != cudaSuccess) {
        printf( "%s in %s at line %d\n", cudaGetErrorString( err ),
                file, line );
        exit( EXIT_FAILURE );
    }
}

static void __cudaCheckError( const char *file, const int line )
{

	cudaError_t err = cudaGetLastError();
    if ( cudaSuccess != err )
    {
        fprintf( stderr, "cudaCheckError() failed at %s:%i : %s\n",
                 file, line, cudaGetErrorString( err ) );
        exit( -1 );
    }
}

#define HANDLE_ERROR( err ) (HandleError( err, __FILE__, __LINE__ ))
#define CudaCheckError()    __cudaCheckError( __FILE__, __LINE__ )
#ifdef __cplusplus
}
#endif

#endif /* _VIS_SIM_H_ */
