# AquaLogic Project Context

## What This Paper Is About
AquaLogic is a project documentation paper for JRed Aquatics, a small aquaculture business in Novaliches, Caloocan City that also operates a food service side business. The system being proposed combines IoT-based water monitoring with a fish information management system to improve aquarium care, reduce manual work, and support better operational decisions.

## Client and Setting
- Client: JRed Aquatics
- Location: Villa Magdalena, Camarin Road, Novaliches, Caloocan City
- Business type: Ornamental fish breeding and sales, aquarium supplies and maintenance, plus an eatery
- Core need: Maintain healthy water conditions and organize fish care data in one system

## Main Problem
The business currently relies on manual monitoring and manual aquarium management. That creates delays, inconsistent readings, and a higher risk of fish stress or loss. Fish care information is also not centralized, so staff may not always have fast access to accurate species-specific guidance.

## Proposed Solution
AquaLogic is designed as an IoT and automation-based system with:
- Real-time water monitoring using sensors for temperature, pH, turbidity, dissolved oxygen, TDS, and ammonia
- A web-based monitoring dashboard for staff
- An automated rule-based decision engine for analysis and recommendations
- Automated aquarium controls for chemical dosing, partial water replacement, lighting, filtration/UV sterilization, and fish feeding
- A centralized fish information database

## Technical Direction
The paper describes a dual-device setup:
- ESP32 handles sensor collection and actuator control
- Raspberry Pi 5 acts as the local dashboard server and hosts the decision engine
- Communication happens over local Wi-Fi using HTTP/HTTPS and JSON

The system emphasizes practical automation with safety limits, manual overrides, and local buffering if the connection drops.

## Project Scope
In scope:
- IoT monitoring and dashboard
- Fish information database
- Automated feeding, lighting, filtration, chemical dosing, and partial water replacement
- Scheduling interface for staff
- Testing, calibration, and deployment at JRed Aquatics

Out of scope:
- Online sales or e-commerce
- Customer mobile app
- Multi-branch expansion
- Advanced commercial-grade automation
- Long-term maintenance beyond the project timeline

## Timeline and Deliverables
The project runs from March 2026 to October 2026 and is structured into phases for initiation, planning, design, development, testing, deployment, and final evaluation. The main deliverable is a working AquaLogic system with integrated hardware, dashboard, automation features, and documentation.

## Budget and ROI
- Total project cost: ₱235,390.00
- Total annual benefits: ₱312,000.00
- Net gain in year 1: ₱76,610.00
- Estimated ROI: about 32.5%
- Estimated payback period: about 9 months

## Key Business Value
The paper frames AquaLogic as a way to:
- Improve water quality management
- Reduce staff workload
- Lower fish mortality and treatment costs
- Improve customer satisfaction through healthier fish
- Give management better data for decisions

## Short Working Summary
If we talk about this paper later, treat it as a project proposal and charter for a smart aquatics system that uses IoT sensors, automation, and a fish information database to help JRed Aquatics manage aquarium health more consistently and efficiently.