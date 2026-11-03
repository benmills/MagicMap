import { parseMesh, meshNormals } from "./terrain-scene.mjs";
self.onmessage = ({ data: { id, buffer, spatialIndex, offset } }) => {
  try {
    const mesh = parseMesh(buffer, { spatialIndex, offset });
    mesh.normals = meshNormals(mesh);
    delete mesh.vertex;
    self.postMessage({ id, mesh }, [
      mesh.positions.buffer,
      mesh.indices.buffer,
      mesh.normals.buffer,
    ]);
  } catch (error) {
    self.postMessage({ id, error: error.message });
  }
};
