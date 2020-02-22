# Two Phase Flow

This is a WIP prototyping test bed for real time GPU simulation of two phase flow.

![Sample Image](https://github.com/rawrunprotected/two_phase_flow/blob/master/Images/SampleImage.png)

## License

This project is licensed under the terms of GPL v3 as it includes codelets generated using [FFTW](https://github.com/FFTW/fftw3).

## Requirements and Running

- Visual Studio 2019
- A DX11-capable graphics card (tested with GTX 1080)
- Open the solution file, press F5.

## Implementation Details

The end goal is producing a visually intriguing real time simulation of level-set-based two phase flow, including physical effects such as high viscosity and surface tension. This enables simulating scenarios that aren't easily achievable with usual particle based simulations, such as simulating liquid metal pooling on the ground due to extremely high surface tension, or simulating a drop of viscous honey flowing down the side of a container.

Here "real time" fluid simulation is defined as fitting a simulation step and rendering into <16ms on a high end consumer GPU. Simulation time doesn't necessarily have to correspond to wall time, but rather should be within a factor of real time that still allows visuals interesting enough to watch.

The primary technical considerations are near-unconditional stability of all solver stepping schemes, as well as preserving level set integrity, to avoid both blow up or vanishing mass across large time steps and time scales. To achieve this goal, the following schemes are used:

- Advection: Using the classical [Semi-Lagrangian scheme](https://en.wikipedia.org/wiki/Semi-Lagrangian_scheme).
- Incompressibility: Using the projection method using a DFT-based solver.
- Viscosity: Using a first order implicit scheme with a multi-grid solver.
- Surface tension: Using a semi-implicit level set diffusion scheme to stabilize curvature estimation based on the recent [Georges-Henri Cottet, Emmanuel Maitre. A semi-implicit level set method for multiphase flows and fluid-structure interaction problems](https://hal.archives-ouvertes.fr/hal-01188443/file/ls_imp_final.pdf).

Rendering is based on raymarching the level set.

## Planning and TODOs

- Full technical documentation on solver details.
- Make simulation based on actual physical units.
- Camera controls.
- Some debugging / visualization tools for particle and ray tracing.
- Presets to load various simulation scenarios (e.g. water/oil layer inversion, honey drop, liquid metal, syrup mixing).
- Remove Bousinessq bouyancy approximation and add full support for non-constant density via iterative spectral pressure solver.
- Better level set maintenance (more accurate zero level reconstruction, full jump flooding). Possibly using coupled volume-of-fluid solution.
- In-depth performance optimizations; most optimizations so far are made in algorithmic design choices rather than low-level implementation.
- Correct boundary conditions for viscosity and surface tension (to specify contact angles).
- Improving convergence order of the schemes used as most are only first order for the initial implementation.
