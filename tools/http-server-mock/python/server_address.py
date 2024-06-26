#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import socket

class ServerAddress():
	def __init__(self, ip, port):
		self.ip = ip
		self.port = port

def get_private_IP():
	"""
	Returns private IP on the local network or `None` if the local network is not reachable.
    """

	s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	try:
		s.connect(('10.255.255.255', 1))
		return ServerAddress(s.getsockname()[0], 8000)
	except:
		return None
	finally:
		s.close()

def get_localhost():
	"""
	Returns localhost address.
    """

	return ServerAddress('127.0.0.1', 8000)

def get_best_server_address():
	"""
	Returns private IP if possible, localhost otherwise.
    """

	private_ip = get_private_IP()
	return private_ip if private_ip is not None else get_localhost()

if __name__ == "__main__":
	address = get_best_server_address()
	print("{ip}:{port}".format( ip = address.ip, port = address.port))
