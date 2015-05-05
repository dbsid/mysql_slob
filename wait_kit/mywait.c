#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <sys/time.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <string.h>

/*
 * * Copyright (c) 1999 Peak Performance Systems
 * * All rights reserved.
 * *
 * * Author: Kevin Closson
 * *
 * * Permission to use, copy, modify, and distribute this software and its
 * * documentation for any purpose, without fee, and without written agreement is
 * * hereby granted, provided that the above copyright notice and the following
 * * two paragraphs appear in all copies of this software.
 *
 * * IN NO EVENT SHALL PEAK PERFORMANCE SYSTEMS, OR ANY OF ITS AGENTS, BE LIABLE TO
 * * ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
 * * ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF PEAK
 * * PERFORMANCE SYSTEMS HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * * PEAK PERFORMANCE SYSTEMS DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED
 * * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
 * * THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND PEAK PERFORMANCE SYSTEMS
 * * HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 * */

int
wait_for_trigger ()
{
  int sem_id;
  struct sembuf sem_ops[1];
  key_t key;
  key_t ftok ();

  key = ftok ("./trigger", 1);
  sem_id = semget (key, 1, 0660);
  if (sem_id < 0)
    {
      perror ("semget failed");
      exit (errno);
    }

  sem_ops[0].sem_num = 0;
  sem_ops[0].sem_op = 0;
  sem_ops[0].sem_flg = 0;
  semop (sem_id, sem_ops, 1);
  return 0;
}


int
main ()
{
	(int) wait_for_trigger ();
	return 0;
}
