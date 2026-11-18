# A requirement under `packages:all` with `when: "%cxx"` is applied to packages that have no C++ dependency

## Summary

A conditional requirement on all packages whose condition is a bare language virtual,
such as `when: "%cxx"`, is also applied to packages that do not depend on `cxx`.
Concretization then fails, because the requirement gives such a package a C++
compiler that its recipe does not allow.

Writing the condition with the provider, `when: "%cxx=gcc"`, behaves as expected.

## Steps to reproduce

With a system GCC registered by `spack compiler find` and no other configuration:

```yaml
# packages.yaml
packages:
  all:
    require:
    - spec: "%cxx=gcc"
      when: "%cxx"
```

```console
$ spack spec --fresh zlib
==> Error: failed to concretize `zlib` for the following reasons:
     1. gmake cannot have a dependency on cxx

$ spack spec --fresh json-c
==> Error: failed to concretize `json-c` for the following reasons:
     1. Only external, or concrete, compilers are allowed for the c language

$ spack spec --fresh cmake
==> Error: failed to concretize `cmake` for the following reasons:
     1. Only external, or concrete, compilers are allowed for the c language

$ spack spec --fresh libmd
 -   libmd@1.1.0 build_system=autotools ... %c=gcc@14.4.1
```

## Run it

The [`reproduce` workflow](.github/workflows/reproduce.yml) runs
[`reproduce.sh`](reproduce.sh) on Ubuntu 24.04 with Spack v1.2.2 and with the
develop branch, on every push and once a week. A job is red while the bug is
there, and turns green once every spec concretizes.

Locally, with `gcc` and `g++` on `PATH` and any Spack checkout:

```console
$ git clone --depth 1 --branch v1.2.2 https://github.com/spack/spack.git
$ ./reproduce.sh spack
```

The script uses a configuration and a cache of its own below `./work`. It reads
and changes no Spack configuration of the user.

## Expected

The requirement reads "a package that depends on `cxx` takes it from gcc". The
system gcc is the only compiler, so every spec above should concretize exactly as
it does without the requirement:

- `gmake` and `json-c` depend on `c` only, so the condition is false for them and
  nothing is required of them.
- `zlib` and `cmake` depend on `cxx`, and take it from gcc already.

## Actual

- `zlib` fails with `gmake cannot have a dependency on cxx`. `gmake` is a build
  dependency of `zlib`, which uses C++; `gmake` itself does not.
- `json-c`, a C-only CMake package, and `cmake` fail with
  `Only external, or concrete, compilers are allowed for the c language`.
  `json-c` depends directly on `cmake`, which uses C++.
- `libmd`, a C-only package with no dependency that uses C++, concretizes.

So the condition appears to hold for a package when a package next to it in the
DAG depends on `cxx`: a direct dependency (`json-c` -> `cmake`) or a dependent
(`zlib` -> `gmake`).

With `when: "%cxx=gcc"` in place of `when: "%cxx"`, the same specs concretize.

## Versions

The same behaviour with the system GCC as the only compiler:

- Spack 1.2.2 (3e19345b6e12f5ff1b874f4059622fc6a1fd804a) on Rocky Linux 10, GCC 14.4.1, and on Ubuntu 24.04
- Spack 1.3.0.dev0, develop at 7188f9d6e0f345d023d1f947401eeaaf5ced9f5f (2026-11-18), on Rocky Linux 10, GCC 14.4.1

## Notes

- The toolchains documentation uses the same condition, `when: "%cxx"`, to mean
  "whenever the package uses that language", which is the meaning expected here.
- Not traced in the solver. A possible starting point is how a condition on a
  `virtual_node` is satisfied in `lib/spack/spack/solver/concretize.lp`; this is a
  guess from the symptoms, not a finding.
- Spack also warns that the requirement "applies a dependency constraint to all
  packages" and suggests `packages:cxx:require`. That form is not an alternative
  where the compiler is itself a reused package built by another compiler, since
  it then also applies to the compiler's own dependencies.
