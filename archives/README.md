# Downloaded archive fixtures

`benchmark.ps1` resolves the pinned SDK and runtime assets from the official
[.NET 11 release metadata](https://builds.dotnet.microsoft.com/dotnet/release-metadata/11.0/releases.json),
downloads missing `.tar.gz` files, validates their published SHA-512 hashes,
and generates the matching uncompressed `.tar` files.

The downloaded and generated archives are ignored by Git. They are retained
locally so benchmark timing excludes download and decompression setup.

| Product | Version | Published archive SHA-512 |
|---|---|---|
| .NET SDK | `11.0.100-rc.1.26425.128` | `649a2fa79b2588a3a0c59a9ea054e800fcdb77afe47e6a9b60b22c522b11e4bef1992423ea59ad0d5499b509f4a5752aa69df964c36b9a7e3bcffd2a0748361d` |
| .NET Runtime | `11.0.0-rc.1.26425.128` | `714ff8edc1b0f0ff9831439e38188182cc0cbc210d5119301395ebf80b63f490062cdd4c47c2c311a8541ef3b7774a735855e77649b57b34c668deed97914c66` |

The `.tar` files are direct decompressions of their matching `.tar.gz` files.
