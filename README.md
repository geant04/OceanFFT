# Unity Oceans, a dive into learning FFTs

![movingOceanPreview](https://github.com/user-attachments/assets/93681505-294e-476d-afc6-b712b591e738)

WIP ocean simulation done in Unity, using compute shaders for IFFT calculations

Features:
- Phillips Spectrum to generate ocean spectra
- IFFT Tessendorf wave displacement and normal calculations, simulating over 260k waves
- Detailed water lighting shader using methods from Atlas, presented at GDC 2019
- Simple tile system with culling, allowing dynamic camera motion

Future features:
- Tiling and blending on the ocean surface itself, faster than simulating cascades, method from Ubisoft and presented at HPG 24

References:
- https://tore.tuhh.de/bitstreams/8dc34c7a-f9f1-4d34-bebe-d397ac76b9f4/download
- https://www.keithlantz.net/2011/10/ocean-simulation-part-one-using-the-discrete-fourier-transform/
- https://github.com/achalpandeyy/OceanFFT
- https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/OceanCS_Slides.pdf
- https://www.ubisoft.com/en-us/studio/laforge/news/5WHMK3tLGMGsqhxmWls1Jw/making-waves-in-ocean-surface-rendering-using-tiling-and-blending
