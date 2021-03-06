#include <cuda.h>
#include <cuda_runtime_api.h>
//#include <device_functions.h>
//#define _USE_MATH_DEFINES
//#include <math.h>
#include "vis_sim.h"

texture<float, 3, cudaReadModeElementType> tex;

__global__ void find_vis( float *baseline, float *src_dir, float *src_int, float *src_index, float *freqs, float* mfreqs, int *N_fq_p, int *N_src_p, float *vis_arr, cudaArray *beam_arr, float *lmin_p, float *lmax_p, float *mmin_p, float *mmax_p, float *beamfqmin_p, float *beamfqmax_p) {
	//Inputs: Baseline is length 3 vector in nanoseconds, src_dir is N_src*3 array, src_int is an N_src array, src_index is a N_src array, freqs is an N_fq array of frequencies in GHz, mfreqs is an N_src array
	//Outputs: vis_arr is a N_fq complex array holding the computed visibility with real and imaginary parts interleaved.
	int N_fq   = *N_fq_p;
	int N_src  = *N_src_p;
	float lmin = *lmin_p;
	float lmax = *lmax_p;
	float mmin = *mmin_p;
	float mmax = *mmax_p;
	float beamfqmin = *beamfqmin_p;
	float beamfqmax = *beamfqmax_p;
	float coeff, dot=0, fq;
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	int sid = blockIdx.y * blockDim.y + threadIdx.y;
	
	if (tid >= N_fq || sid >= N_src) return;
	fq = freqs[tid];
	// Find the position in normalized texture array coordinates
	float l_norm = (src_dir[3*sid]   - lmin)/(lmax - lmin);
	float m_norm = (src_dir[3*sid+1] - mmin)/(mmax - mmin);
	float fq_norm = (fq - beamfqmin)/(beamfqmax - beamfqmin);
	for (int i=0 ; i < 3 ; i++) {//compute the dot product of baseline and source direction
		dot += src_dir[3*sid+i] * baseline[i];
	}
	dot *= -2 * CL_M_PI_F;
	float texel = tex3D(tex, l_norm, m_norm, fq_norm);
	coeff = src_int[sid] * powf(fq/mfreqs[sid], src_index[sid]) * texel;
	vis_arr[2*(N_src*tid + sid)  ] = coeff * cosf(fq*dot);
	vis_arr[2*(N_src*tid + sid)+1] = coeff * sinf(fq*dot);
}

__global__ void sum_vis(float *vis_arr, float *sum_vis_arr, int *N_fq_p, int *N_src_p) {
    int N_fq = *N_fq_p;
    int N_src = *N_src_p;
    int tid = blockIdx.x;
    if (tid >= N_fq) return;
    sum_vis_arr[2*tid  ] = 0;
    sum_vis_arr[2*tid+1] = 0;
    for(int i=0 ; i < N_src ; i++){//iterate over all sources
        sum_vis_arr[2*tid  ] += vis_arr[2*(N_src*tid+i)  ];
        sum_vis_arr[2*tid+1] += vis_arr[2*(N_src*tid+i)+1];
    }
}

int vis_sim(float *baseline, float *src_dir, float *src_int, float *src_index,
            float *freqs, float *mfreqs, float *vis_arr, float *beam_arr,
            int l, int m, int N_beam_fq, float lmin, float lmax, float mmin, float mmax,
            float beamfqmin, float beamfqmax, int N_fq, int N_src){
	float *dev_baseline, *dev_src_dir, *dev_src_int, *dev_src_index, *dev_freqs, *dev_mfreqs,
		*dev_vis_arr, *dev_sum_vis_arr,*dev_lmin, *dev_lmax,
		*dev_mmin, *dev_mmax, *dev_beamfqmin, *dev_beamfqmax;
	int *dev_N_fq, *dev_N_src;
	cudaArray *dev_beam_arr;
	cudaExtent beam_arr_size = make_cudaExtent(l, m, N_beam_fq);
	cudaChannelFormatDesc channelDesc = cudaCreateChannelDesc<float>();

	// Allocate memory on the GPU
	HANDLE_ERROR(cudaMalloc((void**) &dev_baseline,      3*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_src_dir,       3*N_src*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_src_int,       N_src*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_src_index,     N_src*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_freqs,         N_fq*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_mfreqs,        N_src*sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_vis_arr,       2 * N_fq * N_src * sizeof(float)));	    
	HANDLE_ERROR(cudaMalloc((void**) &dev_sum_vis_arr,   2 * N_fq * sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_N_fq,          sizeof(int)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_N_src,         sizeof(int)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_lmin,          sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_lmax,          sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_mmin,          sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_mmax,          sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_beamfqmin,     sizeof(float)));
	HANDLE_ERROR(cudaMalloc((void**) &dev_beamfqmax,     sizeof(float)));
    
    //Allocate memory for beam_arr.  
    HANDLE_ERROR(cudaMalloc3DArray(&dev_beam_arr, &channelDesc, beam_arr_size));
	
	// Move the arrays onto the GPU
	HANDLE_ERROR(cudaMemcpy(dev_baseline,  baseline,  3*sizeof(float),       cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_src_dir,   src_dir,   3*N_src*sizeof(float), cudaMemcpyHostToDevice));    
	HANDLE_ERROR(cudaMemcpy(dev_src_int,   src_int,   N_src*sizeof(float),   cudaMemcpyHostToDevice));    
	HANDLE_ERROR(cudaMemcpy(dev_src_index, src_index, N_src*sizeof(float),   cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_freqs,     freqs,     N_fq*sizeof(float),    cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_mfreqs,    mfreqs,    N_src*sizeof(float),   cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_N_fq,      &N_fq,      sizeof(int),    cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_N_src,     &N_src,     sizeof(int),    cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_lmin,      &lmin,      sizeof(float),  cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_lmax,      &lmax,      sizeof(float),  cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_mmin,      &mmin,      sizeof(float),  cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_mmax,      &mmax,      sizeof(float),  cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_beamfqmin, &beamfqmin, sizeof(float),  cudaMemcpyHostToDevice));
	HANDLE_ERROR(cudaMemcpy(dev_beamfqmax, &beamfqmax, sizeof(float),  cudaMemcpyHostToDevice));

	//Copy the beam_arr array onto the GPU
	cudaMemcpy3DParms copyParams = {0};
	copyParams.srcPtr   = make_cudaPitchedPtr((void*)beam_arr,  beam_arr_size.width*sizeof(float), beam_arr_size.width, beam_arr_size.height);
	copyParams.dstArray = dev_beam_arr;
	copyParams.extent   = beam_arr_size;
	copyParams.kind     = cudaMemcpyHostToDevice;
	HANDLE_ERROR(cudaMemcpy3D(&copyParams));

	//set Texture parameters
	tex.normalized = true;
	tex.filterMode = cudaFilterModeLinear;
	tex.addressMode[0] = cudaAddressModeClamp; // XXX should maybe make this Border to set out-of-range vals to 0
	tex.addressMode[1] = cudaAddressModeClamp; // XXX should maybe make this Border to set out-of-range vals to 0
	tex.addressMode[2] = cudaAddressModeClamp;
    

	//bind array to texture
	HANDLE_ERROR(cudaBindTextureToArray(tex, dev_beam_arr, channelDesc));

	dim3 grid(N_fq, N_src);
    
	find_vis<<<grid,1>>>(dev_baseline, dev_src_dir, dev_src_int, dev_src_index, dev_freqs, dev_mfreqs, 
                        dev_N_fq, dev_N_src, dev_vis_arr, dev_beam_arr, dev_lmin, dev_lmax, 
                        dev_mmin, dev_mmax, dev_beamfqmin, dev_beamfqmax);
    CudaCheckError();
	sum_vis<<<N_fq,1>>>(dev_vis_arr, dev_sum_vis_arr, dev_N_fq, dev_N_src);
    CudaCheckError();
	// copy the array back
	HANDLE_ERROR(cudaMemcpy(vis_arr, dev_sum_vis_arr, 2 * N_fq * sizeof(float), cudaMemcpyDeviceToHost));
	
	//frees memory allocated on GPU
	cudaFree(dev_baseline);
	cudaFree(dev_src_dir);
	cudaFree(dev_src_int);
	cudaFree(dev_src_index);
	cudaFree(dev_freqs);
	cudaFree(dev_mfreqs);
	cudaFree(dev_vis_arr);
	cudaFree(dev_sum_vis_arr);
	cudaFree(dev_N_fq);
	cudaFree(dev_N_src);
	cudaFreeArray(dev_beam_arr);
	cudaFree(dev_lmin);
	cudaFree(dev_lmax);
	cudaFree(dev_mmin);
	cudaFree(dev_mmax);
	cudaFree(dev_beamfqmin);
	cudaFree(dev_beamfqmax);

	return 0;
}
