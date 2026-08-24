export class ShardedPMTilesSource {
  constructor(baseUrl, manifest, key, onChunkLoad = () => {}) {
    this.baseUrl = baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`;
    this.manifest = manifest;
    this.key = key;
    this.onChunkLoad = onChunkLoad;
    this.cache = new Map();
  }

  getKey() {
    return this.key;
  }

  async loadChunk(index, signal) {
    if (!this.cache.has(index)) {
      const promise = fetch(new URL(this.manifest.chunks[index].name, this.baseUrl), {
        signal,
        cache: "force-cache",
      }).then(async (response) => {
        if (!response.ok) throw new Error(`Chunk ${index} gagal dimuat (${response.status})`);
        const data = await response.arrayBuffer();
        this.onChunkLoad(data.byteLength, index);
        return new Uint8Array(data);
      });
      this.cache.set(index, promise);
    }
    return this.cache.get(index);
  }

  async getBytes(offset, length, signal) {
    const first = Math.floor(offset / this.manifest.chunk_size);
    const last = Math.floor((offset + length - 1) / this.manifest.chunk_size);
    const indices = [];
    for (let index = first; index <= last; index += 1) indices.push(index);
    const chunks = await Promise.all(indices.map((index) => this.loadChunk(index, signal)));
    const result = new Uint8Array(length);
    let written = 0;
    for (let index = 0; index < chunks.length; index += 1) {
      const chunkStart = indices[index] * this.manifest.chunk_size;
      const from = Math.max(offset, chunkStart) - chunkStart;
      const to = Math.min(offset + length, chunkStart + chunks[index].byteLength) - chunkStart;
      const slice = chunks[index].subarray(from, to);
      result.set(slice, written);
      written += slice.byteLength;
    }
    return { data: result.buffer };
  }
}

export async function loadShardedManifest(path) {
  const manifestUrl = new URL(`${import.meta.env.BASE_URL}${path}`, window.location.origin);
  const response = await fetch(manifestUrl);
  if (!response.ok) throw new Error(`Manifest PMTiles gagal dimuat (${response.status})`);
  return { manifestUrl, manifest: await response.json() };
}
