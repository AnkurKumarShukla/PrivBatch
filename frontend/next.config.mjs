/** @type {import('next').NextConfig} */
const nextConfig = {
  webpack: (config) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    config.externals.push("pino-pretty", "lokijs", "encoding");
    // Fix for MetaMask SDK requiring react-native-async-storage
    config.resolve.alias = {
      ...config.resolve.alias,
      "@react-native-async-storage/async-storage":
        "next/dist/build/polyfills/object-assign.js",
    };
    return config;
  },
};

export default nextConfig;
