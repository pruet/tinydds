//$Id: OneHopM.nc,v 1.41 2009/09/07 21:26:45 pruet Exp pruet $
// Ported to 2.0

/*Copyright (c) 2008, 2009 University of Massachusetts, Boston 
All rights reserved. 
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

	Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
	Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
    Neither the name of the University of Massachusetts, Boston  nor 
the names of its contributors may be used to endorse or promote products 
derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE UNIVERSITY OF
MASSACHUSETTS, BOSTON OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, 
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING 
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
POSSIBILITY OF SUCH DAMAGE.
*/

//This file is generated from IDL. please use it as the skelton file for your module
#include <stdio.h>
#include <stdlib.h>

module OneHopM {
	provides {
		 interface L3;
	}
	uses {
		 interface Boot;
		 interface AMSend;
		 interface Receive;
		 interface Packet;
         interface LocalTime<TMilli>;
		 interface SplitControl as AMControl;
		 interface Leds;
		 interface Printf;
		 interface Topology;
	}
} implementation {
	nx_uint16_t _dests[MAX_NEIGHBOR];
	message_t packet;
	Neighbors _neighbors[MAX_NEIGHBOR];
	nx_uint16_t DEFAULT;
	uint8_t __lock;

	typedef nx_struct data_msg {
		nx_uint16_t src;
		nx_uint16_t orig;
		nx_uint8_t topic;
		nx_uint32_t sec;
		nx_uint32_t nanosec;
		nx_uint8_t size;
		nx_uint8_t subject;
		nx_uint8_t	data[MAX_DATA_LEN];
	} Data_Msg;
	typedef Data_Msg *Data_Msg_Ptr;
	Data_Msg _buffers[MAX_BUFFER_SIZE];

	void initBuffer()
	{
		int k;
		for(k = 0; k != MAX_BUFFER_SIZE; k++) {
			_buffers[k].src = DEFAULT;
		}
	}

	int getBufferSize()
	{
		int k;
		int count = 0;
		for(k = 0; k != MAX_BUFFER_SIZE; k++) {
			if(_buffers[k].src != DEFAULT) 	count++;
		}
		return count;
	}

	int addBuffer(Data_Msg data, nx_uint16_t dest)
	{
		int k;
		for(k = 0; k != MAX_BUFFER_SIZE; k++) {
			if(_buffers[k].src == DEFAULT) {
				data.src = TOS_NODE_ID;
				memcpy( &_buffers[k], &data, sizeof(Data_Msg));
				_dests[k] = dest;
				return RETCODE_OK;
			}
		}
		return RETCODE_ERROR;
	}

	int getBuffer(Data_Msg *data, nx_uint16_t *dest)
	{
		int k;
		for(k = 0; k != MAX_BUFFER_SIZE; k++) {
			if(_buffers[k].src != DEFAULT) {
				memcpy(data, &_buffers[k], sizeof(Data_Msg));
				_buffers[k].src = DEFAULT;
				*dest = _dests[k];
				return RETCODE_OK;
			}
		}
		return RETCODE_ERROR;
	}

	void initNeighbors()
	{
		int k;
		for(k = 0; k != MAX_NEIGHBOR; k++) {
			_neighbors[k].id = DEFAULT;
			_neighbors[k].dist = DEFAULT;
			_neighbors[k].status = DEFAULT;
		}
	}

	int getNeighborSize()
	{
		int k;
		int j = 0;
		for(k = 0; k != MAX_NEIGHBOR; k++) {
			if(_neighbors[k].id != DEFAULT) j++;
		}
		return j;
	}

	int addNeighbor(nx_uint16_t id)
	{
		int k;
		for(k = 0; k != MAX_NEIGHBOR; k++) {
			if(_neighbors[k].id == DEFAULT) {
				_neighbors[k].id = id;
				return RETCODE_OK;
			} 
			if(_neighbors[k].id == id) {
				return RETCODE_OK;
			}
		}
		return RETCODE_ERROR;
	}

	uint8_t isNeighbor(nx_uint16_t nid)
	{
		int k;
		for(k = 0; k != MAX_NEIGHBOR; k++) {
			if(_neighbors[k].id == nid) {
				return TRUE;
			}
		}
		return FALSE;
	}

	nx_uint16_t* getNeighborList()
	{
		int k;
		int j = 1;
		nx_uint16_t *list = (nx_uint16_t *)malloc(sizeof(nx_uint16_t) * (MAX_NEIGHBOR + 1));
		for(k = 0; k != MAX_NEIGHBOR; k++) {
			if(_neighbors[k].id != DEFAULT) {
				list[j] = _neighbors[k].id;
				j++;
			}
		}
		list[0] = j -1;
		return list;
	}

	task void send_message() 
	{
		nx_uint16_t dest;
		Data_Msg_Ptr m;
		bool status = FALSE;
		call Leds.led0Toggle();
		atomic {
			if(__lock == 0) {
				m = (Data_Msg_Ptr)(call Packet.getPayload(&packet, sizeof(Data_Msg)));
				if(m == NULL) {
					call Printf.printf("m is null");
				} else {
					if(getBuffer(m, &dest) == RETCODE_OK) {
						__lock = 1;

						if(call AMSend.send((uint32_t)dest, &packet, sizeof(Data_Msg)) == SUCCESS) {
							status = TRUE;
						} else {
							status = FALSE;
						}
						__lock = 0;
					}
				}
			} else {
				post send_message();
			}
		}
		if(status) {
			call Printf.printf("oh:send ok");
		} else {
			call Printf.printf("oh:send fail");
		}
	}

	event void Boot.booted()
	{
		dbg("L3", "OH:%s:called\n", __FUNCTION__);
		DEFAULT = 0xFFFF;
		initNeighbors();
		initBuffer();
		__lock = 0;
		call AMControl.start();
	}

	event void AMControl.startDone(error_t err) {
		dbg("L3", "OH:%s:called\n", __FUNCTION__);
		if(err != SUCCESS) {
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err) {
		dbg("L3", "OH:%s:called\n", __FUNCTION__);
	}


	event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len)
	{
		char buf[20];
		call Leds.led1Toggle();
		if(len == sizeof(Data_Msg)) {
			Data data;
			Data_Msg_Ptr data_msg_ptr = (Data_Msg_Ptr) payload;
			if((call Topology.isNeighbor(data_msg_ptr->src)) == FALSE) {
				sprintf(buf, "oh:!nei:%d:%d", TOS_NODE_ID, data_msg_ptr->src);
				call Printf.printf(buf);
				return bufPtr;
			}
			addNeighbor(data_msg_ptr->src);
			call Printf.printf("oh:rcv");
			dbg("L3", "OH:%s:called Receive:data:%d:%d:%d:%d:%s\n", __FUNCTION__, data_msg_ptr->src, data_msg_ptr->orig, data_msg_ptr->subject, data_msg_ptr->topic, data_msg_ptr->data);
			data.timestamp.sec = data_msg_ptr->sec;
			data.timestamp.nanosec = data_msg_ptr->nanosec;
			data.topic = data_msg_ptr->topic;
			data.size = data_msg_ptr->size;
			data.orig = data_msg_ptr->orig;
			data.src = data_msg_ptr->src;
			data.subject = data_msg_ptr->subject;
			memcpy(data.item, data_msg_ptr->data, (data.size > MAX_DATA_LEN)?MAX_DATA_LEN:data.size);
			signal L3.receive(data_msg_ptr->src, data);
		}
		return bufPtr;
	}

	event void AMSend.sendDone (message_t* sentBuffer, error_t err) 
	{
		dbg("L3", "OH:%s:called\n", __FUNCTION__);
		atomic {
			if(&packet == sentBuffer) {
				dbg("L3", "OH:%s:status %d\n", __FUNCTION__, err);
			}
			if(getBufferSize() != 0) {
				post send_message();
			}
			__lock = 0;
		}
	}

	command ReturnCode_t L3.send (nx_uint16_t dest, Data data)
	{
		nx_uint16_t len;
		Data_Msg msg;
		dbg("L3", "OH:%s:called\n", __FUNCTION__);
		//FIXME: should not be hardcoded the TOS_BCAST_ADDR here
		//if(isNeighbor(dest) == FALSE && dest != 0xFFFF) {
		//return RETCODE_ERROR;
		//}
		msg.src = TOS_NODE_ID;	
		msg.orig = data.orig;
		msg.sec = data.timestamp.sec;
		msg.nanosec = data.timestamp.nanosec;
		msg.size = data.size;
		msg.topic = data.topic;
		msg.subject = data.subject;
		if(data.subject == SUBJECT_DATA) {
			data.item[10]++;
			dbg("L3", "OH:%s:subject %d:trans count %d \n", __FUNCTION__, data.subject, data.item[10]);
		}
		memcpy(msg.data, data.item, (data.size > MAX_DATA_LEN)?MAX_DATA_LEN:data.size);
		len = sizeof(Data_Msg) + MAX_DATA_LEN;
		dbg("L3", "OH:%s:send to %d len %d time %d\n", __FUNCTION__, dest, len, call LocalTime.get());
		if(addBuffer(msg, dest) == RETCODE_OK) {
			dbg("L3", "OH:%s:buffer added\n", __FUNCTION__);
			post send_message();
		} else {
			dbg("L3", "OH:%s:buffer added failed\n", __FUNCTION__);
		}
		return RETCODE_OK;
	}

	command nx_uint16_t * L3.get_neighbors()
	{
		return getNeighborList();
	}
}
