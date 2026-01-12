using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode] 
public class WaterBody : MonoBehaviour
{
    [Header("Rendering")] [Tooltip("液体网格")] public Mesh mesh;
    [Tooltip("液体网格的子网格索引")] public int subMeshIndex = 0;
    [Tooltip("液体材质")] public Material material;
    [Tooltip("是否使用网格的世界坐标高度范围计算水平面(否则就用包围盒简化)")] public bool useRealHeightRange;
    [Tooltip("包围盒中心点")] public Vector3 boxCenter = Vector3.zero;
    [Tooltip("包围盒大小")] public Vector3 boxSize = Vector3.one;
    [Header("Physics-Wobble")] [Tooltip("最大旋转角度"), Range(0f, 90f)] public float maxAngle = 90f;
    [Tooltip("最大旋转量")] public float maxWobble = 0.03f;
    [Tooltip("旋转加速度")] public float wobbleSpeed = 1f;
    [Tooltip("恢复水平的速度")] public float recoverySpeed = 1f;
    private bool isStartUpdateWobble;
    private Vector3 lastPos;
    private Vector3 velocity;
    private Vector3 lastRot;
    private Vector3 angularVelocity;
    private Vector3 wobbleAmount;
    private Vector3 wobbleAmountToAdd;
    private float wobbleTimer;
    private float lastWobbleTime;
    
    private void OnEnable()
    {
        UpdateHeight();
    }
    private void Start()
    {
        lastPos = transform.position;
        lastRot = transform.rotation.eulerAngles;
        material.SetFloat("_MaxAngle", maxAngle);
    }
    private void Update()
    {
        if (transform.hasChanged)
        {
            UpdateHeight();
            isStartUpdateWobble = true;
            transform.hasChanged = false;
        }
        if (UnityEngine.Application.isPlaying && isStartUpdateWobble)
            UpdateWobble();
    }
    private void OnDrawGizmos()
    {
        if (!useRealHeightRange)
        {
            Gizmos.matrix = transform.localToWorldMatrix;
            Gizmos.DrawWireCube(boxCenter, boxSize);
        }
    }
    /// <summary> 模拟晃动</summary>
    private void UpdateWobble()
    {
        Debug.Log("Update Wobble");
        wobbleTimer += Time.deltaTime;
        // decrease wobble over time
        wobbleAmountToAdd = Vector3.Lerp(wobbleAmountToAdd, Vector3.zero, Time.deltaTime * recoverySpeed);
        // make a sine wave of the decreasing wobble
        wobbleAmount = wobbleAmountToAdd * Mathf.Sin(2 * Mathf.PI * wobbleSpeed * wobbleTimer);
        // velocity
        velocity = (lastPos - transform.position) / Time.deltaTime;
        angularVelocity = transform.rotation.eulerAngles - lastRot;
        // add clamped velocity to wobble
        wobbleAmountToAdd.x += Mathf.Clamp((velocity.z + (angularVelocity.x * 0.5f)) * maxWobble, -maxWobble, maxWobble);
        wobbleAmountToAdd.z += Mathf.Clamp((velocity.x + (angularVelocity.z * 0.5f)) * maxWobble, -maxWobble, maxWobble);
        // keep last position
        lastPos = transform.position;
        lastRot = transform.rotation.eulerAngles;
        // stop
        if (wobbleTimer - lastWobbleTime > 0.01f && wobbleAmountToAdd.sqrMagnitude < 0.001f)
        {
            lastWobbleTime = wobbleTimer;
            isStartUpdateWobble = false;
            wobbleAmountToAdd = wobbleAmount = Vector3.zero;
        }
        // send it to the shader
        material.SetVector("_Wobble", new Vector4(
            wobbleAmount.x, wobbleAmount.y, wobbleAmount.z, Mathf.Clamp01(wobbleAmountToAdd.magnitude)));
    }
    /// <summary> 更新高度范围 </summary>
    private void UpdateHeight()
    {
        Debug.Log("Update Height");
        float minHeight = float.MaxValue, maxHeight = float.MinValue;
        if (useRealHeightRange)
        {
            List<Vector3> vertices = new List<Vector3>();
            mesh.GetVertices(vertices);
            if (mesh.subMeshCount > 1)
            {
                int[] subMeshIndexs = mesh.GetIndices(subMeshIndex);
                for (int i = 0; i < subMeshIndexs.Length; i++)
                {
                    Vector3 worldPos = transform.TransformPoint(vertices[subMeshIndexs[i]]);
                    if (worldPos.y < minHeight)
                        minHeight = worldPos.y;
                    if (worldPos.y > maxHeight)
                        maxHeight = worldPos.y;
                }
            }
            else
            {
                for (int i = 0; i < vertices.Count; i++)
                {
                    Vector3 worldPos = transform.TransformPoint(vertices[i]);
                    if (worldPos.y < minHeight)
                        minHeight = worldPos.y;
                    if (worldPos.y > maxHeight)
                        maxHeight = worldPos.y;
                }
            }
        }
        else
        {
            Vector3[] cornerPoints = new Vector3[8];
            cornerPoints[0] = boxCenter + 0.5f * new Vector3(boxSize.x, boxSize.y, boxSize.z);
            cornerPoints[1] = boxCenter + 0.5f * new Vector3(-boxSize.x, boxSize.y, boxSize.z);
            cornerPoints[2] = boxCenter + 0.5f * new Vector3(boxSize.x, -boxSize.y, boxSize.z);
            cornerPoints[3] = boxCenter + 0.5f * new Vector3(boxSize.x, boxSize.y, -boxSize.z);
            cornerPoints[4] = boxCenter + 0.5f * new Vector3(-boxSize.x, -boxSize.y, boxSize.z);
            cornerPoints[5] = boxCenter + 0.5f * new Vector3(boxSize.x, -boxSize.y, -boxSize.z);
            cornerPoints[6] = boxCenter + 0.5f * new Vector3(-boxSize.x, boxSize.y, -boxSize.z);
            cornerPoints[7] = boxCenter + 0.5f * new Vector3(-boxSize.x, -boxSize.y, -boxSize.z);
            for (int i = 0; i < cornerPoints.Length; i++)
            {
                Vector3 worldPos = transform.TransformPoint(cornerPoints[i]);
                if (worldPos.y < minHeight)
                    minHeight = worldPos.y;
                if (worldPos.y > maxHeight)
                    maxHeight = worldPos.y;
            }
        }
        material.SetVector("_WorldHeightRange", new Vector2(minHeight, maxHeight));
    }
    
}