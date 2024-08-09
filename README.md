# Unity Oceans, FFT

![movingOceanPreview](https://github.com/user-attachments/assets/93681505-294e-476d-afc6-b712b591e738)

WIP ocean simulation done in Unity, using compute shaders for IFFT calculations
Features:
- Phillips Spectrum to generate ocean spectra
- IFFT Tessendorf wave displacement and normal calculations, rendering over 260k waves
- Detailed water lighting shader using methods from Atlas
- Simple tile system with culling

References:
https://tore.tuhh.de/bitstreams/8dc34c7a-f9f1-4d34-bebe-d397ac76b9f4/download
https://www.keithlantz.net/2011/10/ocean-simulation-part-one-using-the-discrete-fourier-transform/
https://github.com/achalpandeyy/OceanFFT
https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/OceanCS_Slides.pdf
