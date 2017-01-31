##~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~##
##                                                                                   ##
##  This file forms part of the Badlands surface processes modelling application.    ##
##                                                                                   ##
##  For full license and copyright information, please refer to the LICENSE.md file  ##
##  located at the project root, or contact the authors.                             ##
##                                                                                   ##
##~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~##
"""
This module encapsulates functions related to Badlands surface elevation.
"""

import time
import numpy
from pyBadlands.libUtils import PDalgo
import warnings

from scipy.interpolate import interpn
from scipy.interpolate import LinearNDInterpolator
from scipy.interpolate import NearestNDInterpolator

def _boundary_elevation(elevation, neighbours, edge_length, boundPts, btype):
    """
    This function defines the elevation of the TIN surface edges for 2 different types of conditions:
        1. Infinitely flat condition,
        2. Continuous slope condition.

    Parameters
    ----------
    variable : elevation
        Numpy arrays containing the internal nodes elevation.

    variable : neighbours
        Numpy integer-type array containing for each nodes its neigbhours IDs.

    variable : edge_length
        Numpy float-type array containing the lengths to each neighbour.

    variable : boundPts
        Number of nodes on the edges of the TIN surface.

    variable : btype
        Integer defining the type of boundary: 0 for flat and 1 for slope condition.

    Return
    ----------
    variable: elevation
        Numpy array containing the updated elevations on the edges.
    """

    # Flat
    if btype == 0:
        missedPts = []
        for id in range(boundPts):
            ngbhs = neighbours[id,:]
            ids = numpy.where(ngbhs >= boundPts)[0]
            if len(ids) == 1:
                elevation[id] = elevation[ngbhs[ids]]
            elif len(ids) > 1:
                lselect = edge_length[id,ids]
                picked = numpy.argmin(lselect)
                elevation[id] = elevation[ngbhs[ids[picked]]]
            else:
                missedPts = numpy.append(missedPts,id)

        if len(missedPts) > 0 :
            for p in range(len(missedPts)):
                id = int(missedPts[p])
                ngbhs = neighbours[id,:]
                ids = numpy.where((elevation[ngbhs] < 9.e6) & (ngbhs >= 0))[0]
                if len(ids) == 0:
                    raise ValueError('Error while getting boundary elevation for point ''%d''.' % id)
                lselect = edge_length[id,ids]
                picked = numpy.argmin(lselect)
                elevation[id] = elevation[ngbhs[ids[picked]]]

    # Slope
    elif btype == 1:
        missedPts = []
        for id in range(boundPts):
            ngbhs = neighbours[id,:]
            ids = numpy.where(ngbhs >= boundPts)[0]
            if len(ids) == 1:
                # Pick closest non-boundary vertice
                ln1 = edge_length[id,ids[0]]
                id1 = ngbhs[ids[0]]
                # Pick closest non-boundary vertice to first picked
                ngbhs2 = neighbours[id1,:]
                ids2 = numpy.where(ngbhs2 >= boundPts)[0]
                lselect = edge_length[id1,ids2]
                if len(lselect) > 0:
                    picked = numpy.argmin(lselect)
                    id2 = ngbhs2[ids2[picked]]
                    ln2 = lselect[picked]
                    elevation[id] = (elevation[id1]-elevation[id2])*(ln2+ln1)/ln2 + elevation[id2]
                else:
                    missedPts = numpy.append(missedPts,id)
            elif len(ids) > 1:
                # Pick closest non-boundary vertice
                lselect = edge_length[id,ids]
                picked = numpy.argmin(lselect)
                id1 = ngbhs[ids[picked]]
                ln1 = lselect[picked]
                # Pick closest non-boundary vertice to first picked
                ngbhs2 = neighbours[id1,:]
                ids2 = numpy.where(ngbhs2 >= boundPts)[0]
                lselect2 = edge_length[id1,ids2]
                if len(lselect2) > 0:
                    picked2 = numpy.argmin(lselect2)
                    id2 = ngbhs2[ids2[picked2]]
                    ln2 = lselect2[picked2]
                    elevation[id] = (elevation[id1]-elevation[id2])*(ln2+ln1)/ln2 + elevation[id2]
                else:
                    missedPts = numpy.append(missedPts,id)
            else:
                missedPts = numpy.append(missedPts,id)

        if len(missedPts) > 0 :
            for p in range(0,len(missedPts)):
                id = int(missedPts[p])
                ngbhs = neighbours[id,:]
                ids = numpy.where((elevation[ngbhs] < 9.e6) & (ngbhs >= 0))[0]
                if len(ids) == 0:
                    raise ValueError('Error while getting boundary elevation for point ''%d''.' % id)
                lselect = edge_length[id,ids]
                picked = numpy.argmin(lselect)
                elevation[id] = elevation[ngbhs[ids[picked]]]

    return elevation

def update_border_elevation(elev, neighbours, edge_length, boundPts, btype='flat'):
    """
    This function computes the domain boundary elevation for 3 different types of conditions:
        1. Infinitely flat condition,
        2. Continuous slope condition,
        3. Wall boundary (closed domain).

    Parameters
    ----------
    variable : elev
        Numpy arrays containing the internal nodes elevation.

    variable : neighbours
        Numpy integer-type array containing for each nodes its neigbhours IDs.

    variable : edge_length
        Numpy float-type array containing the lengths to each neighbour.

    variable : boundPts
        Number of nodes on the edges of the TIN surface.

    variable : btype
        Integer defining the type of boundary. Possible conditions are:
            1. wall
            2. flat: this is the default condition
            3. slope

    Return
    ----------
    variable: newelev
        Numpy array containing the updated elevations on the edges.
    """

    newelev = elev

    if btype == 'wall':
        newelev[:boundPts] = 1.e7

    elif btype == 'flat' or btype == 'slope':
        newelev[:boundPts] = 1.e7
        thetype = 0
        if btype == 'slope':
            thetype = 1

        newelev = _boundary_elevation(elev, neighbours, edge_length, boundPts, thetype)
    else:
        raise ValueError('Unknown boundary type ''%s''.' % btype)

    return newelev

def getElevation(rX, rY, rZ, coords, interp='linear'):
    """
    This function interpolates elevation from a regular grid to a cloud of points using SciPy interpolation.

    Parameters
    ----------
    variable : rX, rY, rZ
        Numpy arrays containing the X, Y & Z coordinates from the regular grid.

    variable : coords
        Numpy float-type array containing X, Y coordinates for the TIN nodes.

    variable : interp
        Define the interpolation technique as in SciPy interpn function. The default is 'linear'

    Return
    ----------
    variable: elev
        Numpy array containing the updated elevations for the local domain.
    """

    # Set new elevation to 0
    elev = numpy.zeros(len(coords[:,0]))

    # Get the TIN points elevation values using the regular grid dataset
    elev = interpn( (rX, rY), rZ, (coords[:,:2]), method=interp)

    return elev

def assign_parameter_pit(neighbours, edge_length, area, diffslp, boundPts, fillTH=1., epsilon=0.01):
    """
    This function defines global variables used in the pit filling algorithm.

    Parameters
    ----------
    variable : neighbours
        Numpy integer-type array containing for each nodes its neigbhours IDs.

    variable : edge_length
        Numpy float-type array containing the lengths to each neighbour.

    variable : area
        Numpy float-type array containing the area of each cell.

    variable : diffslp
        Marine diffusion slope value.

    variable : boundPts
        Number of nodes on the edges of the TIN surface.

    variable : fillTH
        Limit the filling algorithm to a specific height to prevent complete filling of depression.
        Default is set to 1.0 metre.

    variable : epsilon
        Force a minimal slope to form the depression instead of a flat area to build continuous flow
        pathways. Default is set to 0.01 metres.
    """

    PDalgo.pdstack.pitparams(neighbours, edge_length, area, diffslp, fillTH, epsilon, boundPts)


def pit_stack_PD(elev, allFill, sealevel):
    """
    This function calls a depression-less algorithm from Planchon & Darboux to compute the flow
    pathway using stack.

    Parameters
    ----------
    variable : elev
        Numpy arrays containing the nodes elevation.

    variable : allFill
        Produce depression-less surface.

    variable : sealevel
        Current elevation of sea level.

    Return
    ----------
    variable: fillH
        Numpy array containing the filled elevations.
    """

    # Call stack based pit filling function from libUtils
    fillH = PDalgo.pdstack.pitfilling(elev, allFill, sealevel)

    return fillH
