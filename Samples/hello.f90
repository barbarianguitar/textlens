program hello
  implicit none
  integer :: i
  real :: total
  total = 0.0

  do i = 1, 3
    total = total + real(i) * 1.5
    print *, "HELLO", i, total
  end do

  if (total > 5.0) then
    print *, 'done'   ! Fortran 90 free-form comment
  end if
end program hello
