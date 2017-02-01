##~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~##
##                                                                                   ##
##  This file forms part of the Badlands surface processes modelling application.    ##
##                                                                                   ##
##  For full license and copyright information, please refer to the LICENSE.md file  ##
##  located at the project root, or contact the authors.                             ##
##                                                                                   ##
##~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~##
"""
This file is the main entry point to compute flow network and associated sedimentary fluxes.
"""

import time
import numpy as np
import mpi4py.MPI as mpi
from matplotlib import path

from pyBadlands import (elevationTIN)

def streamflow(input, FVmesh, recGrid, force, hillslope, flow, elevation, \
                 lGIDs, rain, tNow, verbose=False):
    """
    Compute flow network.
    """

    rank = mpi.COMM_WORLD.rank
    size = mpi.COMM_WORLD.size
    comm = mpi.COMM_WORLD

    flow.Flow_time = time.clock()

    # Update sea-level
    walltime = time.clock()
    force.getSea(tNow)
    fillH = None

    # Update river input
    force.getRivers(tNow)
    riverrain = rain+force.rivQw

    # Build an initial depression-less surface at start time if required
    if input.tStart == tNow and input.nopit == 1 :
        fillH = elevationTIN.pit_stack_PD(elevation,input.nopit,force.sealevel)
        elevation = fillH
    else:
        fillH = elevationTIN.pit_stack_PD(elevation,0,force.sealevel)

    if rank == 0 and verbose and input.spl:
        print " -   depression-less algorithm PD with stack", time.clock() - walltime

    # Compute stream network
    walltime = time.clock()
    flow.SFD_receivers(fillH, elevation, FVmesh.neighbours,
                       FVmesh.vor_edges, FVmesh.edge_length,
                       lGIDs)

    if rank == 0 and verbose:
        print " -   compute receivers parallel ", time.clock() - walltime

    # Distribute evenly local minimas to processors on filled surface
    walltime = time.clock()
    flow.localbase = np.array_split(flow.base, size)[rank]
    flow.ordered_node_array_filled()
    if rank == 0 and verbose:
        print " -   compute stack order locally for filled surface", time.clock() - walltime

    walltime = time.clock()
    stackNbs = comm.allgather(len(flow.localstack))
    globalstack = np.zeros(sum(stackNbs), dtype=flow.localstack.dtype)
    comm.Allgatherv(sendbuf=[flow.localstack, mpi.INT],
                    recvbuf=[globalstack, (stackNbs, None), mpi.INT])
    flow.stack = globalstack
    if rank == 0 and verbose:
        print " -   send stack order for filled surface globally ", time.clock() - walltime

    # Distribute evenly local minimas on real surface
    walltime = time.clock()
    flow.localbase1 = np.array_split(flow.base1, size)[rank]
    flow.ordered_node_array_elev()
    if rank == 0 and verbose:
        print " -   compute stack order locally for real surface", time.clock() - walltime

    walltime = time.clock()
    stackNbs1 = comm.allgather(len(flow.localstack1))
    globalstack1 = np.zeros(sum(stackNbs1), dtype=flow.localstack1.dtype)
    comm.Allgatherv(sendbuf=[flow.localstack1, mpi.INT],
                    recvbuf=[globalstack1, (stackNbs1, None), mpi.INT])
    flow.stack1 = globalstack1
    if rank == 0 and verbose:
        print " -   send stack order for real surface globally ", time.clock() - walltime

    # Compute a unique ID for each local depression and their downstream draining nodes
    flow.compute_parameters_depression(fillH,elevation,FVmesh.control_volumes,force.sealevel)

    # Compute discharge
    walltime = time.clock()
    flow.compute_flow(FVmesh.control_volumes, riverrain)
    if rank == 0 and verbose:
        print " -   compute discharge ", time.clock() - walltime

    return fillH, elevation

def sediment_flux(input, recGrid, hillslope, FVmesh, tMesh, flow, force, lGIDs, applyDisp, \
                  mapero, cumdiff, fillH, disp, inGIDs, elevation, tNow, tEnd, verbose=False):
    """
    Compute sediment fluxes.
    """

    rank = mpi.COMM_WORLD.rank
    size = mpi.COMM_WORLD.size
    comm = mpi.COMM_WORLD

    # Compute CFL condition
    walltime = time.clock()
    if input.Hillslope:
        hillslope.dt_stability(FVmesh.edge_length[inGIDs,:tMesh.maxNgbh])
    else:
        hillslope.CFL = tEnd-tNow
    flow.dt_stability(fillH, inGIDs)
    CFLtime = min(flow.CFL, hillslope.CFL)
    if CFLtime>1.:
        CFLtime = float(round(CFLtime-0.5,0))
    if rank == 0 and verbose:
        print 'CFL for hillslope and flow ',hillslope.CFL,flow.CFL,CFLtime
    CFLtime = min(CFLtime, tEnd - tNow)
    CFLtime = max(input.minDT, CFLtime)
    CFLtime = min(input.maxDT, CFLtime)
    if rank == 0 and verbose:
        print " -   Get CFL time step ", time.clock() - walltime

    # Compute sediment fluxes
    # Initial cumulative elevation change
    walltime = time.clock()
    xyMin = [recGrid.regX.min(), recGrid.regY.min()]
    xyMax = [recGrid.regX.max(), recGrid.regY.max()]
    domain = path.Path([(xyMin[0],xyMin[1]),(xyMax[0],xyMin[1]), (xyMax[0],xyMax[1]), (xyMin[0],xyMax[1])])
    insideIDs = domain.contains_points(flow.xycoords)

    ids = np.where(force.rivQs>0)
    tmp = force.rivQs[ids]
    timestep, sedrate = flow.compute_sedflux(FVmesh.control_volumes, elevation, fillH, xyMin, xyMax,
                                          CFLtime, force.rivQs, force.sealevel, cumdiff,
                                          input.perc_dep, input.slp_cr, input.diffsigma, verbose)
    if rank == 0 and verbose:
        print " -   Get stream fluxes ", time.clock() - walltime

    # Update surface parameters
    elevation += sedrate
    cumdiff += sedrate

    # Compute hillslope processes
    walltime = time.clock()
    flow.compute_hillslope_diffusion(elevation, FVmesh.neighbours,
                       FVmesh.vor_edges, FVmesh.edge_length,lGIDs)
    cdiff = hillslope.sedflux(flow.diff_flux, force.sealevel, elevation, FVmesh.control_volumes)
    diff_flux = np.zeros(len(cdiff))
    diff_flux[insideIDs] = cdiff[insideIDs]
    diff = diff_flux * timestep
    elevation += diff
    cumdiff += diff
    if rank == 0 and verbose:
        print " -   Get hillslope fluxes ", time.clock() - walltime

    if applyDisp:
        elevation += disp * timestep

    # Update erodibility values
    if input.erolays >= 0:
        mapero.getErodibility(diff)
        flow.erodibility = mapero.erodibility

    tNow += timestep

    if rank == 0 and verbose:
        print " - Flow computation ", time.clock() - flow.Flow_time

    return tNow,elevation,cumdiff
