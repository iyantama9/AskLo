const { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');

// Lazy initialization to ensure env vars are loaded
let minioClient = null;

function getMinioClient() {
  if (!minioClient) {
    minioClient = new S3Client({
      region: 'us-east-1', // MinIO doesn't care about region but SDK requires it
      endpoint: `http://${process.env.MINIO_ENDPOINT}`,
      credentials: {
        accessKeyId: process.env.MINIO_ACCESS_KEY,
        secretAccessKey: process.env.MINIO_SECRET_KEY,
      },
      forcePathStyle: true, // Required for MinIO
    });
  }
  return minioClient;
}

const BUCKET = process.env.MINIO_BUCKET || 'askcore-files';

/**
 * Upload file to MinIO
 */
async function uploadFile(key, buffer, contentType, metadata = {}) {
  const command = new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: buffer,
    ContentType: contentType,
    Metadata: metadata,
  });

  await getMinioClient().send(command);
  return { key, bucket: BUCKET };
}

/**
 * Get file from MinIO
 */
async function getFile(key) {
  const command = new GetObjectCommand({
    Bucket: BUCKET,
    Key: key,
  });

  const response = await getMinioClient().send(command);
  return response.Body;
}

/**
 * Get file metadata
 */
async function getFileMetadata(key) {
  const command = new HeadObjectCommand({
    Bucket: BUCKET,
    Key: key,
  });

  return await getMinioClient().send(command);
}

/**
 * Delete file from MinIO
 */
async function deleteFile(key) {
  const command = new DeleteObjectCommand({
    Bucket: BUCKET,
    Key: key,
  });

  await getMinioClient().send(command);
}

/**
 * Generate public URL for MinIO files
 */
function getPublicUrl(key) {
  const publicPrefix = process.env.MINIO_PUBLIC_URL_PREFIX || process.env.PUBLIC_BASE_URL;
  if (publicPrefix) {
    const normalized = publicPrefix.replace(/\/+$/, '');
    if (normalized.endsWith('/api/files')) {
      return `${normalized}/${key}`;
    }
    return `${normalized}/api/files/${key}`;
  }

  const useSSL = process.env.MINIO_USE_SSL === 'true';
  const protocol = useSSL ? 'https' : 'http';
  const publicEndpoint = process.env.MINIO_PUBLIC_ENDPOINT || process.env.MINIO_ENDPOINT;
  return `${protocol}://${publicEndpoint}/${BUCKET}/${key}`;
}

module.exports = {
  getMinioClient,
  uploadFile,
  getFile,
  getFileMetadata,
  deleteFile,
  getPublicUrl,
  BUCKET,
};
