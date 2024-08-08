using System.Collections;
using System.Collections.Generic;
using UnityEngine;


[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class PostProcessFog : MonoBehaviour
{
    private Material FogMaterial;
    public Shader FogShader;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (FogMaterial != null)
        {
            Graphics.Blit(source, destination, FogMaterial);
        } 
        else
        {
            Graphics.Blit(source, destination);
        }
    }

    private void Start()
    {
        if (FogMaterial == null)
        {
            FogMaterial = new Material(FogShader);
        }

        GetComponent<Camera>().depthTextureMode = DepthTextureMode.Depth;
    }

    private void Update()
    {
        Matrix4x4 projMatrix = GL.GetGPUProjectionMatrix(Camera.main.projectionMatrix, false);
        Matrix4x4 viewProjMatrix = projMatrix * Camera.main.worldToCameraMatrix;

        FogMaterial.SetMatrix("_InverseViewProjection", viewProjMatrix);
    }
}
