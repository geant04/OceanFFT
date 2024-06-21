using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OceanScript : MonoBehaviour
{
    Mesh mesh;
    Material OceanMaterial;

    // Shaders + Compute Shader params
    public ComputeShader OceanComputeShader;
    private int threadGroupsX, threadGroupsY;

    public Shader OceanShader;

    // SerializeFields
    [SerializeField] Vector2 size = new Vector2(1,1);
    [SerializeField] int planeResolution = 1;
    [SerializeField] int N = 32;
    [SerializeField] int L = 64;
    
    // RenderTextures
    private RenderTexture heightMap,
                          normalMap,
                          initialSpectrum,
                          spectrumTexture,
                          butterfly;

    public RenderTexture FFTBuffer;
    
    // Misc.
    Vector3[] vertices;
    private int prevN;
    private int prevL;

    void CreatePlane()
    {
        this.GetComponent<MeshFilter>().mesh = mesh = new Mesh();
        mesh.name = "Ocean Mesh";
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        vertices = new Vector3[(planeResolution + 1) * (planeResolution + 1)];
        float xPerStep = size.x / planeResolution;
        float zPerStep = size.y / planeResolution;


        Vector2[] uvs = new Vector2[vertices.Length];
        Vector4[] tangents = new Vector4[vertices.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);

        // this is a neat i = 0 trick to get the index
        for (int i = 0, z = 0; z < planeResolution + 1; z++) {
            for (int x = 0; x < planeResolution + 1; x++, i++) {
                vertices[i] = new Vector3(((float)x * xPerStep) - (size.y / 2) , 0, ((float)z * zPerStep) - (size.y / 2));
                uvs[i] = new Vector2((float)x / planeResolution, (float)z / planeResolution);
                tangents[i] = tangent;
            }
        }

        mesh.vertices = vertices;
        mesh.uv = uvs;
        mesh.tangents = tangents;

        int[] triangles = new int[planeResolution * planeResolution * 6];
        
        for (int row = 0; row < planeResolution; row++) {
            for (int column = 0; column < planeResolution; column++) {
                int i = (row * (planeResolution + 1) + column);
                int idx = (row * planeResolution + column) * 6;

                triangles[idx] = i;
                triangles[idx + 1] = i + planeResolution + 1;
                triangles[idx + 2] = i + planeResolution + 2;

                triangles[idx + 3] = i;
                triangles[idx + 4] = i + planeResolution + 2;
                triangles[idx + 5] = i + 1;
            }
        }

        mesh.triangles = triangles;
    }

    void CreateMaterial()
    {
        OceanMaterial = new Material(OceanShader);
        OceanMaterial.name = "Ocean Material";
        GetComponent<MeshRenderer>().material = OceanMaterial;
    }

    RenderTexture CreateRenderTexture(int width, int height, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.useMipMap = useMips;
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.autoGenerateMips = false;
        
        rt.Create();
        return rt;
    }

    void InitializeSimulation()
    {
        prevN = N;
        prevL = L;

        CreatePlane();
        CreateMaterial();

        int logN = (int)Mathf.Log(N, 2);
        threadGroupsX = Mathf.CeilToInt(N / 8.0f);
        threadGroupsY = threadGroupsX;

        // Create the initial spectrum  texture -- should this require mips? Experiment with this
        initialSpectrum = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Generate initial Phillips spectrum
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetInt("_HorizontalPatch", L);
        OceanComputeShader.SetTexture(0, "InitialSpectrum", initialSpectrum);
        OceanComputeShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);

        // Create the spectrum texture
        spectrumTexture = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // Create height map texture
        heightMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Create normal map texture
        normalMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);

        // Create buffer texture
        FFTBuffer = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // Create Butterfly texture
        GenerateButterfly();
    }

    void GenerateButterfly()
    {
        int logN = (int)Mathf.Log(N, 2);

        Debug.Log(logN);

        butterfly = CreateRenderTexture(logN, N, RenderTextureFormat.ARGBFloat, false);
        butterfly.filterMode = FilterMode.Point;

        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_GenerateButterfly"), "ButterflyTexture", butterfly);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_GenerateButterfly"), threadGroupsX, threadGroupsY, 1);
    }

    void ButterflyPass(bool PingPong)
    {
        if (butterfly == null)
        {
            GenerateButterfly();
        }

        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_ButterflyPass"), threadGroupsX, threadGroupsY, 1);
    }

    void GenerateSpectrum()
    {
        threadGroupsX = Mathf.CeilToInt(N / 8.0f);
        threadGroupsY = threadGroupsX;

        // After generating h0k + h0minusk, we compute h_tilde
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), "InitialSpectrum", initialSpectrum);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), "Spectrum", spectrumTexture);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_GenerateSpectrum"), threadGroupsX, threadGroupsY, 1);
    }

    void InversionPermutePass(bool PingPong, RenderTexture PingPong0, RenderTexture PingPong1)
    {
        OceanComputeShader.SetBool("_PingPong", PingPong);
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong0", PingPong0);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "PingPong1", PingPong1);
        OceanComputeShader.SetTexture(OceanComputeShader.FindKernel("CS_InvertPermute"), "Displacement", heightMap);
        OceanComputeShader.Dispatch(OceanComputeShader.FindKernel("CS_InvertPermute"), threadGroupsX, threadGroupsY, 1);
    }

    void IFFT(RenderTexture PingPong0, RenderTexture PingPong1)
    {
        bool PingPong = false;
        int logN = (int)Mathf.Log(N, 2);
        int kernelID = OceanComputeShader.FindKernel("CS_ButterflyPass");

        threadGroupsX = Mathf.CeilToInt(N / 16.0f);
        threadGroupsY = threadGroupsX;

        OceanComputeShader.SetTexture(kernelID, "ButterflyTexture", butterfly);
        OceanComputeShader.SetTexture(kernelID, "PingPong0", PingPong0);
        OceanComputeShader.SetTexture(kernelID, "PingPong1", PingPong1);

        // Horizontal IFFT Pass
        OceanComputeShader.SetBool("_Direction", false);

        for (int i = 0; i < logN; i++)
        {
            OceanComputeShader.SetInt("_Stage", i);
            ButterflyPass(PingPong);
            PingPong = !PingPong;
        }

        /*
        // Vertical IFFT Pass
        OceanComputeShader.SetBool("_Direction", true);

        for (int i = 0; i < logN; i++)
        {
            OceanComputeShader.SetInt("_Stage", i);
            ButterflyPass(PingPong);
            PingPong = !PingPong;
        }*/

        InversionPermutePass(PingPong, PingPong0, PingPong1);
    }

    void Update()
    {
        // If any adjustments to parameters
        if ((N != prevN) || (L != prevL))
        {
            InitializeSimulation();
        }

        OceanComputeShader.SetFloat("_Time", Time.time);

        GenerateSpectrum();
        
        IFFT(spectrumTexture, FFTBuffer);
        //IFFT(true, FFTBuffer, spectrumTexture);

        OceanMaterial.SetTexture("_DisplacementTexture", heightMap);
    }
}
