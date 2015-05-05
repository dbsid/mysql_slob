#include <errno.h>
#include <stdio.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <string.h>
#include <stdlib.h>

/*
* Copyright (c) 1999 Peak Performance Systems
* All rights reserved.
*
* Author: Kevin Closson
*
* Permission to use, copy, modify, and distribute this software and its
* documentation for any purpose, without fee, and without written agreement is
* hereby granted, provided that the above copyright notice and the following
* two paragraphs appear in all copies of this software.

* IN NO EVENT SHALL PEAK PERFORMANCE SYSTEMS, OR ANY OF ITS AGENTS, BE LIABLE TO
* ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
* ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF PEAK
* PERFORMANCE SYSTEMS HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

* PEAK PERFORMANCE SYSTEMS DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED
* TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
* THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND PEAK PERFORMANCE SYSTEMS
* HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
*/


extern int errno;

int
main (argc, argv)
     int argc;
     char **argv;
{
  int sem_id;
  key_t my_key;
  key_t ftok ();

  my_key = ftok ("./trigger", 1);
  sem_id = semget (my_key, 1, 0660);
  if (sem_id < 0)
    {
      perror ("semget");
      return -errno;
    }

  if (semctl (sem_id, 0, IPC_RMID, 0) < 0)
    {
      perror ("semctl");
      return -errno;
    }

  return 0;
}
