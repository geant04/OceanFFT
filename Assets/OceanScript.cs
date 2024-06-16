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
                          spectrumTexture;

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
        this.GetComponent<MeshRenderer>().material = OceanMaterial;
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

    void InverseFFT(RenderTexture target) {
        OceanComputeShader.SetTexture(4, "_FourierTarget", target);
        OceanComputeShader.Dispatch(4, 1, N, 1);

        OceanComputeShader.SetTexture(5, "_FourierTarget", target);
        OceanComputeShader.Dispatch(5, 1, N, 1);
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

        OceanMaterial.SetInt("_L", L);
        OceanMaterial.SetInt("_N", N);

        // Create the initial spectrum  texture -- should this require mips? Experiment with this
        initialSpectrum = CreateRenderTexture(N, N, RenderTextureFormat.RGFloat, true);

        // Tell the compute shaders to fill in our textures now so we can do stuff
        OceanComputeShader.SetInt("_N", N);
        OceanComputeShader.SetInt("_L", L);
        OceanComputeShader.SetTexture(0, "InitialSpectrum", initialSpectrum);
        OceanComputeShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);

        // Create the spectrum texture
        spectrumTexture = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, false);

        // Create height map texture
        heightMap = CreateRenderTexture(N, N, RenderTextureFormat.RGFloat, true);

        // Create normal map texture
        normalMap = CreateRenderTexture(N, N, RenderTextureFormat.ARGBFloat, true);
    }

    void Update()
    {
        // If any adjustments to parameters
        if ((N != prevN) || (L != prevL))
        {
            InitializeSimulation();
        }

        OceanComputeShader.SetFloat("_Time", Time.time);

        OceanComputeShader.SetTexture(1, "InitialSpectrum", initialSpectrum);
        OceanComputeShader.SetTexture(1, "Spectrum", spectrumTexture);
        OceanComputeShader.Dispatch(1, threadGroupsX, threadGroupsY, 1);

        OceanComputeShader.SetTexture(2, "Spectrum", spectrumTexture);
        OceanComputeShader.SetTexture(2, "Displacement", heightMap);
        OceanComputeShader.SetTexture(2, "Normals", normalMap);
        OceanComputeShader.Dispatch(2, threadGroupsX, threadGroupsY, 1);

        OceanMaterial.SetTexture("_DisplacementTexture", heightMap);
    }
}
