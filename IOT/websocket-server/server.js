const WebSocket = require("ws");
const express = require("express");
const request = require("request");
const MjpegConsumer = require("mjpeg-consumer");
const http = require("http");

const CAMERA_STREAM_URL = "http://192.168.137.215/mjpeg/1";
const PORT_STREAM = 3000;
const PORT_DATA = 3001;

const app = express();
const serverStream = http.createServer(app);
const serverData = http.createServer();

// 🟢 WebSocket Stream Server
const wssStream = new WebSocket.Server({ server: serverStream });

wssStream.on("connection", (ws) => {
  console.log("Client connect to get image!");

  const consumer = new MjpegConsumer();
  const req = request({
    url: CAMERA_STREAM_URL,
    timeout: 5000
  }).on('error', (err) => {
    console.error('Error camera:', err.message);
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        error: true,
        message: `Error camera: ${err.message}`
      }));
    }
  });

  req.pipe(consumer).on("data", (frame) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(frame);
    }
  });

  ws.on("close", () => {
    req.destroy();
    console.log("Client connect to get image!");
  });
});

// 🟡 WebSocket Data Server
const wssData = new WebSocket.Server({ server: serverData });

wssData.on("connection", (ws) => {
  console.log("Client connect get data!");
  
  ws.on("message", (message) => {
    try {
      const data = JSON.parse(message.toString());
      console.log("Data from ESP32:", data);
      
      // Broadcast đến tất cả clients
      wssData.clients.forEach(client => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(data));
        }
      });
    } catch (e) {
      console.error("Error parse JSON:", e);
    }
  });
});

// Khởi động server
serverStream.listen(PORT_STREAM, () => {
  console.log(`Stream server running on port ${PORT_STREAM}`);
});

serverData.listen(PORT_DATA, () => {
  console.log(`Data server running on port ${PORT_DATA}`);
});