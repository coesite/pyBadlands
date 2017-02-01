!!~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~!!
!!                                                                                   !!
!!  This file forms part of the Badlands surface processes modelling application.    !!
!!                                                                                   !!
!!  For full license and copyright information, please refer to the LICENSE.md file  !!
!!  located at the project root, or contact the authors.                             !!
!!                                                                                   !!
!!~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~!!

! This module implements flow parameters computation.
module flowcompute

  implicit none

contains

  subroutine discharge(pyStack, pyRcv, pyDischarge, pyDis, pylNodesNb, pygNodesNb)

      integer :: pygNodesNb
      integer :: pylNodesNb
      integer,dimension(pylNodesNb),intent(in) :: pyStack
      integer,dimension(pygNodesNb),intent(in) :: pyRcv
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyDischarge

      real(kind=8),dimension(pygNodesNb),intent(out) :: pyDis

      integer :: n, donor, recvr

      pyDis = pyDischarge

      do n = pylNodesNb, 1, -1
        donor = pyStack(n) + 1
        recvr = pyRcv(donor) + 1
        if( donor /= recvr )then
            pyDis(recvr) = pyDis(recvr) + pyDis(donor)
        endif
      enddo

      return

  end subroutine discharge

  subroutine parameters(pyStack, pyRcv, pyDischarge, pyXY, &
      spl_part, pyBid0, pyChi, pyBasinID, pylNodesNb, pygNodesNb)

      integer :: pygNodesNb
      integer :: pylNodesNb
      integer,intent(in) :: pyBid0
      real(kind=8),intent(in) :: spl_part
      integer,dimension(pylNodesNb),intent(in) :: pyStack
      integer,dimension(pygNodesNb),intent(in) :: pyRcv
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyDischarge
      real(kind=8),dimension(pygNodesNb,2),intent(in) :: pyXY

      integer,dimension(pygNodesNb),intent(out) :: pyBasinID
      real(kind=8),dimension(pygNodesNb),intent(out) :: pyChi

      integer :: n, donor, recvr, bID
      real(kind=8) :: disch1, disch2, dist

      pyChi = 0.
      pyBasinID = -1
      bID = pyBid0
      do n = 1, pylNodesNb
        donor = pyStack(n) + 1
        recvr = pyRcv(donor) + 1
        if(donor == recvr) bID = bID + 1
        pyBasinID(donor) = bID
        disch1 = pyDischarge(donor)
        disch2 = pyDischarge(recvr)
        if( donor /= recvr .and. disch1 > 0. .and. disch2 > 0.)then
            dist = sqrt( (pyXY(donor,1) - pyXY(recvr,1))**2.0 + &
                (pyXY(donor,2) - pyXY(recvr,2))**2.0 )
            pyChi(donor) = pyChi(recvr) + 0.5*((1./disch2)**spl_part + &
                (1./(disch1))**spl_part) * dist
        endif
      enddo

      return

  end subroutine parameters

  subroutine basinparameters(pyStack, pyRcv, pyElev, pyWatH, pyArea, &
    pyBasinID, pyVolume, pylNodesNb, pygNodesNb)

      integer :: pygNodesNb
      integer :: pylNodesNb
      integer,dimension(pylNodesNb),intent(in) :: pyStack
      integer,dimension(pygNodesNb),intent(in) :: pyRcv

      real(kind=8),dimension(pygNodesNb),intent(in) :: pyWatH
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyElev
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyArea

      integer,dimension(pygNodesNb),intent(out) :: pyBasinID
      real(kind=8),dimension(pygNodesNb),intent(out) :: pyVolume

      integer :: n, donor, recvr, pitID

      pyBasinID = -1
      pyVolume = -1
      pitID = -1
      do n = 1, pylNodesNb
        donor = pyStack(n) + 1
        recvr = pyRcv(donor) + 1
        if(donor == recvr)then
          pitID = donor - 1
          pyBasinID(donor) = pitID
        endif
        if(pyWatH(donor) > pyElev(donor) .and. pitID > -1)then
          pyBasinID(donor) = pitID
          pyVolume(pitID+1) = pyVolume(pitID+1) + (pyWatH(donor)-pyElev(donor))*pyArea(donor)
        endif
      enddo

      return

  end subroutine basinparameters

  subroutine basindrainage(orderPits, pitID, pyRcv, pIDs, fillH, &
    sea, pyDrain, pitNb, pygNodesNb)

        integer :: pitNb
        integer :: pygNodesNb
        real(kind=8),intent(in) :: sea
        integer,dimension(pitNb),intent(in) :: orderPits
        integer,dimension(pygNodesNb),intent(in) :: pitID
        integer,dimension(pygNodesNb),intent(in) :: pyRcv
        integer,dimension(pitNb),intent(in) :: pIDs

        real(kind=8),dimension(pygNodesNb),intent(in) :: fillH

        integer,dimension(pygNodesNb),intent(out) :: pyDrain

        integer,dimension(pitNb) :: chainDrain
        integer :: n, donor, recvr, nID, count, p, newDrain
        logical :: newpit,exist

        pyDrain = -1
        chainDrain = -1
        count = 1

        do n = 1, pitNb
          nID = pIDs(orderPits(n)+1) + 1
          donor = nID
          exist = .False.
          if(pyDrain(nID)>-1) exist = .True.
          if(fillH(nID)<sea)then
            exist = .True.
            pyDrain(nID) = nID-1
          endif
          do while(.not. exist)
            recvr = pyRcv(donor) + 1
            ! If this is an internal drained basin or an edge node
            if(recvr == donor)then
              pyDrain(nID) = recvr - 1
              count = 1
              chainDrain = -1
              exist = .True.
            elseif(fillH(recvr)<sea)then
              pyDrain(nID) = recvr - 1
              count = 1
              chainDrain = -1
              exist = .True.
            elseif(pitID(recvr) == -1 .or. pitID(recvr) == nID-1)then
              donor = recvr
            elseif(fillH(pitID(recvr))<sea)then
              donor = recvr
            else
              p = 1
              newpit = .True.
              newDrain = pitID(recvr)
              do while(chainDrain(p) >= 0)
                 if(chainDrain(p)==newDrain) newpit = .False.
                 p = p + 1
              enddo
              if(newpit)then
                chainDrain(p) = newDrain
                pyDrain(nID) = newDrain
                donor = newDrain + 1
                nID = newDrain + 1
              else
                donor = recvr
              endif
            endif
          enddo
        enddo

        return

  end subroutine basindrainage

  subroutine basindrainageall(orderPits, pitID, pyRcv, pIDs, &
    pyDrain, pitNb, pygNodesNb)

        integer :: pitNb
        integer :: pygNodesNb
        integer,dimension(pitNb),intent(in) :: orderPits
        integer,dimension(pygNodesNb),intent(in) :: pitID
        integer,dimension(pygNodesNb),intent(in) :: pyRcv
        integer,dimension(pitNb),intent(in) :: pIDs

        integer,dimension(pygNodesNb),intent(out) :: pyDrain

        integer,dimension(pitNb) :: chainDrain
        integer :: n, donor, recvr, nID, count, p, newDrain
        logical :: newpit,exist

        pyDrain = -1
        chainDrain = -1
        count = 1

        do n = 1, pitNb
          nID = pIDs(orderPits(n)+1) + 1
          donor = nID
          exist = .False.
          if(pyDrain(nID)>-1) exist = .True.
          do while(.not. exist)
            recvr = pyRcv(donor) + 1
            ! If this is an internal drained basin or an edge node
            if(recvr == donor)then
              pyDrain(nID) = recvr - 1
              count = 1
              chainDrain = -1
              exist = .True.
            elseif(pitID(recvr) == -1 .or. pitID(recvr) == nID-1)then
              donor = recvr
            else
              p = 1
              newpit = .True.
              newDrain = pitID(recvr)
              do while(chainDrain(p) >= 0)
                 if(chainDrain(p)==newDrain) newpit = .False.
                 p = p + 1
              enddo
              if(newpit)then
                chainDrain(p) = newDrain
                pyDrain(nID) = newDrain
                donor = newDrain + 1
                nID = newDrain + 1
              else
                donor = recvr
              endif
            endif
          enddo
        enddo

        return

  end subroutine basindrainageall

  subroutine flowcfl(pyIDs, pyRcv, pyXY, pyElev, pyDischarge, Cero, &
      spl_m, spl_n, cfl_dt, pylNodesNb, pygNodesNb)

      integer :: pygNodesNb
      integer :: pylNodesNb
      real(kind=8),intent(in) :: spl_m
      real(kind=8),intent(in) :: spl_n
      integer,dimension(pylNodesNb),intent(in) :: pyIDs
      integer,dimension(pygNodesNb),intent(in) :: pyRcv
      real(kind=8),dimension(pygNodesNb),intent(in) :: Cero
      real(kind=8),dimension(pygNodesNb,2),intent(in) :: pyXY
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyElev
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyDischarge

      real(kind=8),intent(out) :: cfl_dt

      integer :: p, d, r
      real(kind=8) :: dz, tmp, dist

      cfl_dt = 1.e6
      do p = 1, pylNodesNb
        d = pyIDs(p) + 1
        r = pyRcv(d) + 1
        dz = pyElev(d) - pyElev(r)
        if( d /= r .and. dz > 0. .and. pyDischarge(d) > 0.)then
            dist = sqrt( (pyXY(d,1)-pyXY(r,1))**2.0 + (pyXY(d,2)-pyXY(r,2))**2.0 )
            tmp = dist / (Cero(d) * pyDischarge(d)**spl_m * (dz/dist)**(spl_n-1.))
            cfl_dt = min(tmp,cfl_dt)
        endif
      enddo

      return

  end subroutine flowcfl

  subroutine streampower(pyStack, pyRcv, pitID, pitVol, pitDrain, pyXY, pyArea, pyMaxH, &
      pyMaxD, pyDischarge, pyFillH, pyElev, pyRiv, Cero, spl_m, spl_n, perc_dep, &
      slp_cr, sea, dt, borders, pyDepo, pyEro, pylNodesNb, pygNodesNb)

      integer :: pylNodesNb
      integer :: pygNodesNb
      real(kind=8),intent(in) :: dt
      real(kind=8),intent(in) :: sea
      real(kind=8),intent(in) :: spl_n
      real(kind=8),intent(in) :: spl_m
      real(kind=8),intent(in) :: perc_dep
      real(kind=8),intent(in) :: slp_cr
      integer,dimension(pylNodesNb),intent(in) :: pyStack
      integer,dimension(pygNodesNb),intent(in) :: pyRcv
      integer,dimension(pygNodesNb),intent(in) :: pitID
      integer,dimension(pygNodesNb),intent(in) :: borders
      integer,dimension(pygNodesNb),intent(in) :: pitDrain
      real(kind=8),dimension(pygNodesNb,2),intent(in) :: pyXY
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyArea
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyDischarge
      real(kind=8),dimension(pygNodesNb),intent(in) :: Cero
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyMaxH
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyMaxD
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyFillH
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyElev
      real(kind=8),dimension(pygNodesNb),intent(in) :: pyRiv
      real(kind=8),dimension(pygNodesNb),intent(in) :: pitVol

      real(kind=8),dimension(pygNodesNb),intent(out) :: pyDepo
      real(kind=8),dimension(pygNodesNb),intent(out) :: pyEro

      integer :: n, donor, recvr, nID, tmpID
      real(kind=8) :: maxh, SPL, Qs, dh, waterH, erodep, pitDep
      real(kind=8) :: dist, slp, slpdh, updh, tmpdist
      real(kind=8),dimension(pygNodesNb) :: sedFluxes, upZ, updist

      pyDepo = 0.
      pyEro = 0.
      sedFluxes = pyRiv * dt
      upZ = 1.e6
      updist = 0.

      do n = pylNodesNb, 1, -1

        SPL = 0.
        donor = pyStack(n) + 1
        recvr = pyRcv(donor) + 1
        dh = 0.95*(pyElev(donor) - pyElev(recvr))

        if(pyElev(donor) > sea .and. pyElev(recvr) < sea) dh = 0.99*(pyElev(donor) - sea)
        if( dh < 0.001 ) dh = 0.
        waterH = pyFillH(donor)-pyElev(donor)
        dist = sqrt( (pyXY(donor,1)-pyXY(recvr,1))**2.0 + (pyXY(donor,2)-pyXY(recvr,2))**2.0 )

        ! Compute stream power law
        slpdh = 0.
        if( recvr /= donor .and. dh > 0.)then
          ! In case where there is no depression or we are above sea-water
          if(waterH == 0. .and. pyFillH(donor) >= sea)then
            slp = dh/dist

            ! Check if this is an alluvial plain in which case we force deposition
            if(updist(donor) > 0. .and. dist > 0. .and. slp_cr > 0.)then
              updh = upZ(donor) - pyElev(donor)
              if(sedFluxes(donor) > 0. .and. updh/updist(donor) < slp_cr .and. slp < slp_cr .and. updh > 0)then
                slpdh = perc_dep * updh
                slpdh = min(slpdh,pyMaxD(donor))
              endif
            endif

            ! Compute the stream power law expressed in m/y
            if(dist > 0. .and. slpdh == 0.)then
              SPL = -Cero(donor) * (pyDischarge(donor))**spl_m * (slp)**spl_n
            endif
          endif
        endif

        maxh = pyMaxH(donor)
        if(waterH > 0.)then
          maxh = waterH
        elseif(pyElev(donor) < sea)then
          maxh = sea - pyElev(donor)
        elseif(slpdh > 0. .and. slp_cr > 0.)then
          maxh = slpdh
        endif
        maxh = 0.95*maxh

        Qs = 0.
        erodep = 0.
        pitDep = 0.
        ! Erosion case
        if(SPL < 0.)then
          ! Sediment volume [m3]
          erodep = SPL * dt * pyArea(donor)
          Qs = -erodep + sedFluxes(donor)

        ! Deposition case
        elseif( SPL == 0. .and. pyArea(donor) > 0.)then
          ! Fill depression
          if(waterH > 0. .and. pyfillH(donor) > sea)then
            Qs = 0.
            erodep = 0.
            pitDep = sedFluxes(donor)
          ! Marine deposit
          elseif(pyElev(donor) <= sea)then
            ! Add all sediment to the node
            erodep = sedFluxes(donor)
            Qs = 0.
          ! Alluvial plain deposit
          elseif(maxh > 0. .and. waterH == 0. .and. donor /= recvr .and. pyElev(donor) > sea)then
            if(sedFluxes(donor)/pyArea(donor) < maxh)then
              erodep = sedFluxes(donor)
              Qs = 0.
            else
              erodep = maxh*pyArea(donor)
              Qs = sedFluxes(donor) - erodep
            endif
          ! Base-level (sink)
          elseif(donor == recvr .and. pyArea(donor) > 0.)then
            erodep = sedFluxes(donor)
            Qs = 0.
          else
            erodep = 0.
            Qs = sedFluxes(donor)
          endif
        endif

        ! Update sediment volume in receiver node
        if(pitDep==0.)then
          sedFluxes(recvr) = sedFluxes(recvr) + Qs
          if(erodep<0.)then
            pyEro(donor) = pyEro(donor) + erodep
          else
            pyDepo(donor) = pyDepo(donor) + erodep
          endif

        ! In case we fill a depression
        elseif(pitDep>0. .and. pyArea(pitID(donor)+1)>0.)then
          ! Perform distribution
          tmpID = pitID(donor) + 1
          tmpdist = pitDep
          do while(tmpdist > 0.)
            ! In case the depression is underwater
            if(pyfillH(tmpID)<sea)then
              if(pyElev(donor)<sea)then
                pyDepo(donor) = pyDepo(donor) + tmpdist
                tmpdist = 0.
              else
                sedFluxes(recvr) = sedFluxes(recvr) + tmpdist
                tmpdist = 0.
              endif
              nID = recvr
            ! In case the depression is not filled
            elseif(pyDepo(tmpID)+tmpdist<=pitVol(tmpID))then
              pyDepo(tmpID) = pyDepo(tmpID) + tmpdist
              tmpdist = 0.
              nID = tmpID
            ! In case this is an internally drained depression
            elseif(pitDrain(tmpID)+1==tmpID)then
              pyDepo(tmpID) = pyDepo(tmpID) + tmpdist
              tmpdist = 0.
              nID = tmpID
            ! Otherwise get the amount to distibute towards draining basins
            else
              if(borders(tmpID) == 0)then
                 tmpdist = 0.
                 nID = tmpID
              elseif(pyDepo(tmpID)==pitVol(tmpID))then
                 nID = tmpID
              else
                 tmpdist = tmpdist - ( pitVol(tmpID) - pyDepo(tmpID) )
                 pyDepo(tmpID) = pitVol(tmpID)
                 nID = tmpID
              endif
            endif
            tmpID = pitDrain(nID) + 1
          enddo
        endif

        ! For alluvial deposition
        upZ(recvr) = min(pyElev(donor),upZ(recvr))
        if(upZ(recvr)==pyElev(donor)) updist(recvr) = dist

      enddo

      return

  end subroutine streampower

end module flowcompute
