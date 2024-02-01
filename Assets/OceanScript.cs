using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OceanScript : MonoBehaviour
{
    Mesh mesh;
    Material OceanMaterial;

    public ComputeShader OceanComputeShader;
    public Shader OceanShader;

    [SerializeField] Vector2 size = new Vector2(1,1);
    [SerializeField] int planeResolution = 1;

    Vector3[] vertices;
    Vector3[] normals;

    private RenderTexture displacementMap,
                          slopeMap,
                          initialSpectrum;

    public RenderTexture test, spectrum, displacement, slope, butterfly, buffer, displacementX, displacementZ;

    private int threadGroupsX, threadGroupsY;

    private int _N = 512;

    void CreatePlane()
    {
        this.GetComponent<MeshFilter>().mesh = mesh = new Mesh();
        mesh.name = "Ocean Mesh";
        vertices = new Vector3[(planeResolution + 1) * (planeResolution + 1)];
        float xPerStep = size.x / planeResolution;
        float zPerStep = size.y / planeResolution;

        Vector2[] uvs = new Vector2[vertices.Length];
        Vector4[] tangents = new Vector4[vertices.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);

        // this is a neat i = 0 trick to get the index
        for (int i = 0, z = 0; z < planeResolution + 1; z++) {
            for (int x = 0; x < planeResolution + 1; x++, i++) {
                vertices[i] = new Vector3(x * xPerStep, 0, z * zPerStep);
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
                int i = (row * planeResolution + row + column);
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

    void IFFT(RenderTexture InputTexture, RenderTexture bufferTexture, RenderTexture OutTexture, bool outputToInput)
    {
        int logN = (int) Mathf.Log(_N, 2);
        bool pingPong = false;

        OceanComputeShader.SetTexture(4, "pingpong0", InputTexture);
        OceanComputeShader.SetTexture(4, "pingpong1", bufferTexture);
        OceanComputeShader.SetTexture(4, "ButterflyTexture", butterfly);

        for (int i = 0; i < logN; i++) {
            pingPong = !pingPong;
            OceanComputeShader.SetInt("_N", _N);
            OceanComputeShader.SetInt("Stage", i);
            OceanComputeShader.SetBool("PingPong", pingPong);
            OceanComputeShader.Dispatch(4, threadGroupsX, threadGroupsY, 1);
        }

        OceanComputeShader.SetTexture(5, "pingpong0", bufferTexture);
        OceanComputeShader.SetTexture(5, "pingpong1", InputTexture);
        OceanComputeShader.SetTexture(5, "ButterflyTexture", butterfly);

        for (int i = 0; i < logN; i++) {
            pingPong = !pingPong;
            OceanComputeShader.SetInt("_N", _N);
            OceanComputeShader.SetInt("Stage", i);
            OceanComputeShader.SetBool("PingPong", pingPong);
            OceanComputeShader.Dispatch(5, threadGroupsX, threadGroupsY, 1);
        }

        if (pingPong && outputToInput)
        {
            Graphics.Blit(bufferTexture, InputTexture);
        }

        if (!pingPong && !outputToInput)
        {
            Graphics.Blit(bufferTexture, InputTexture);
        }
    }

    void InverseFFT(RenderTexture spectrumTextures) {
        OceanComputeShader.SetTexture(3, "_FourierTarget", spectrumTextures);
        OceanComputeShader.Dispatch(3, 1, _N, 1);
        OceanComputeShader.SetTexture(4, "_FourierTarget", spectrumTextures);
        OceanComputeShader.Dispatch(4, 1, _N, 1);
    }

    void Start()
    {
        CreatePlane();
        CreateMaterial();

        int L = 2000;

        int logN = (int)Mathf.Log(_N, 2);
        threadGroupsX = Mathf.CeilToInt(_N / 8.0f);
        threadGroupsY = threadGroupsX;

        OceanMaterial.SetInt("_L", L);
        OceanMaterial.SetInt("_N", _N);

        // Create the initial spectrum  texture
        initialSpectrum = CreateRenderTexture(_N, _N, RenderTextureFormat.ARGBHalf, true);
        // Tell the compute shaders to fill in our textures now so we can do stuff
        OceanComputeShader.SetInt("_N", _N);
        OceanComputeShader.SetInt("_L", L);
        OceanComputeShader.SetTexture(0, "InitialSpectrum", test);
        OceanComputeShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);

        // generate butterfly texture
        //OceanComputeShader.SetInt("_N", _N);
        //OceanComputeShader.SetTexture(3, "ButterflyTexture", butterfly);
        //OceanComputeShader.Dispatch(3, threadGroupsX, threadGroupsY, 1);
    }

    // Update is called once per frame
    void Update()
    {
        OceanComputeShader.SetFloat("_Time", Time.time);
        //initialSpectrum.GenerateMips();
        
        OceanComputeShader.SetTexture(1, "InitialSpectrum", test);
        OceanComputeShader.SetTexture(1, "Spectrum", spectrum);
        OceanComputeShader.SetTexture(1, "Normals", slope);
        OceanComputeShader.Dispatch(1, threadGroupsX, threadGroupsY, 1);

        /*
        OceanComputeShader.SetTexture(2, "Spectrum", spectrum);
        OceanComputeShader.SetTexture(2, "Displacement", displacement);
        OceanComputeShader.SetTexture(2, "Normals", slope);
        OceanComputeShader.Dispatch(2, threadGroupsX, threadGroupsY, 1);*/

        // FFT time
        //IFFT(spectrum, buffer, displacement, true);
        //IFFT(slope, buffer, slope, true);

        InverseFFT(spectrum);
        InverseFFT(slope);

        OceanComputeShader.SetTexture(5, "Spectrum", spectrum);
        OceanComputeShader.SetTexture(5, "Normals", slope);
        OceanComputeShader.SetTexture(5, "Displacement", displacement);
        OceanComputeShader.Dispatch(5, threadGroupsX, threadGroupsY, 1);

        OceanMaterial.SetTexture("_DisplacementTexture", displacement);
        OceanMaterial.SetTexture("_SlopeTexture", slope);
    }
}
