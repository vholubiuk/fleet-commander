from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel
from enum import Enum
from typing import Optional, List
from datetime import datetime
from prometheus_client import Counter, Gauge, Histogram, make_asgi_app
import random

# Prometheus metrics
REQUESTS_TOTAL = Counter("fleet_requests_total", "Total HTTP requests", ["method", "endpoint", "status"])
SHIPS_ACTIVE = Gauge("fleet_ships_active", "Active ships in fleet")
FLEET_CAPACITY = Gauge("fleet_capacity", "Total fleet capacity (crew slots)")
VOYAGE_DURATION = Histogram("voyage_duration_seconds", "Voyage duration in seconds")

app = FastAPI(
    title="⚓ Fleet Commander - Kubernetes Navigation System",
    description="Manage your fleet of ships sailing the Kubernetes seas"
)

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# ============ Models ============

class ShipStatus(str, Enum):
    DOCKED = "docked"
    SAILING = "sailing"
    ANCHORED = "anchored"
    WRECKED = "wrecked"

class Harbor(BaseModel):
    name: str
    region: str  # e.g., "eastus", "westeurope"
    capacity: int

class Ship(BaseModel):
    ship_id: str
    name: str
    captain: str
    crew_size: int
    status: ShipStatus = ShipStatus.DOCKED
    harbor: str
    cargo: Optional[str] = None
    sailed_at: Optional[datetime] = None

class Voyage(BaseModel):
    voyage_id: str
    ship_id: str
    destination: str
    duration_hours: int
    crew_members: List[str]

# ============ In-Memory Fleet ============

harbors_db = {
    "port-eastus": Harbor(name="Port EastUS", region="eastus", capacity=1000),
    "port-westeu": Harbor(name="Port Western Europe", region="westeurope", capacity=1500),
    "port-asia": Harbor(name="Port Asia Pacific", region="southeastasia", capacity=800),
}

ships_db = {
    "hms-kubernetes": Ship(
        ship_id="hms-kubernetes",
        name="HMS Kubernetes",
        captain="Admiral Kelsey Hightower",
        crew_size=42,
        status=ShipStatus.DOCKED,
        harbor="port-eastus",
        cargo="Container 1.27"
    ),
    "uss-docker": Ship(
        ship_id="uss-docker",
        name="USS Docker",
        captain="Captain Solomon Hykes",
        crew_size=33,
        status=ShipStatus.SAILING,
        harbor="port-westeu",
        cargo="Container Images",
        sailed_at=datetime.now()
    ),
}

voyages_log: List[Voyage] = []

# ============ Middleware ============

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    response = await call_next(request)
    try:
        REQUESTS_TOTAL.labels(
            method=request.method,
            endpoint=request.url.path,
            status=str(response.status_code)
        ).inc()
    except Exception:
        pass
    return response

# ============ Health & Info Endpoints ============

@app.get("/")
async def root():
    return {
        "service": "⚓ Fleet Commander",
        "version": "1.0.0-alpha",
        "description": "Kubernetes management system disguised as a ship fleet",
        "endpoints": {
            "health": "/health",
            "harbors": "/harbors",
            "ships": "/ships",
            "voyages": "/voyages",
            "deploy": "/deploy",
            "metrics": "/metrics"
        }
    }

@app.get("/health")
async def health():
    ships_count = sum(1 for s in ships_db.values() if s.status != ShipStatus.WRECKED)
    SHIPS_ACTIVE.set(ships_count)
    total_crew = sum(s.crew_size for s in ships_db.values())
    FLEET_CAPACITY.set(total_crew)
    
    return {
        "status": "⛵ Fleet is shipshape!",
        "ships_active": ships_count,
        "total_crew": total_crew,
        "harbors": len(harbors_db)
    }

# ============ Harbor Management (like Namespaces) ============

@app.get("/harbors")
async def list_harbors():
    """List all harbors (Kubernetes Namespaces)"""
    return {"harbors": list(harbors_db.values())}

@app.get("/harbors/{harbor_id}")
async def get_harbor(harbor_id: str):
    """Get harbor details"""
    if harbor_id not in harbors_db:
        raise HTTPException(status_code=404, detail=f"Harbor {harbor_id} not found")
    harbor = harbors_db[harbor_id]
    ships_in_harbor = [s for s in ships_db.values() if s.harbor == harbor_id]
    return {
        "harbor": harbor,
        "ships_docked": len(ships_in_harbor),
        "occupancy": sum(s.crew_size for s in ships_in_harbor),
        "capacity": harbor.capacity
    }

# ============ Ship Management (like Pods) ============

@app.get("/ships")
async def list_ships():
    """List all ships in the fleet (Kubernetes Pods)"""
    return {"ships": list(ships_db.values())}

@app.get("/ships/{ship_id}")
async def get_ship(ship_id: str):
    """Get ship details"""
    if ship_id not in ships_db:
        raise HTTPException(status_code=404, detail=f"Ship {ship_id} not found")
    return {"ship": ships_db[ship_id]}

@app.post("/ships")
async def deploy_ship(ship: Ship):
    """Deploy a new ship to the fleet (like kubectl apply -f pod.yaml)"""
    if ship.ship_id in ships_db:
        raise HTTPException(status_code=409, detail=f"Ship {ship.ship_id} already exists")
    if ship.harbor not in harbors_db:
        raise HTTPException(status_code=404, detail=f"Harbor {ship.harbor} not found")
    
    ships_db[ship.ship_id] = ship
    SHIPS_ACTIVE.set(len([s for s in ships_db.values() if s.status != ShipStatus.WRECKED]))
    
    return {
        "status": "deployed",
        "ship": ship,
        "message": f"⚓ {ship.name} has docked at {ship.harbor}"
    }

@app.put("/ships/{ship_id}/sail")
async def set_sail(ship_id: str, destination: str, duration_hours: int = 24):
    """Send a ship on a voyage (like a Deployment rolling out)"""
    if ship_id not in ships_db:
        raise HTTPException(status_code=404, detail=f"Ship {ship_id} not found")
    
    ship = ships_db[ship_id]
    if ship.status == ShipStatus.WRECKED:
        raise HTTPException(status_code=400, detail="Cannot sail a wrecked ship!")
    
    ship.status = ShipStatus.SAILING
    ship.sailed_at = datetime.now()
    
    voyage = Voyage(
        voyage_id=f"voyage-{ship_id}-{int(datetime.now().timestamp())}",
        ship_id=ship_id,
        destination=destination,
        duration_hours=duration_hours,
        crew_members=[ship.captain] + [f"Sailor-{i}" for i in range(ship.crew_size - 1)]
    )
    voyages_log.append(voyage)
    VOYAGE_DURATION.observe(duration_hours * 3600)
    
    return {
        "status": "sailing",
        "ship": ship,
        "voyage": voyage,
        "message": f"⛵ {ship.name} set sail for {destination}!"
    }

@app.put("/ships/{ship_id}/anchor")
async def anchor_ship(ship_id: str, harbor_id: str):
    """Anchor a ship at a harbor (like a node)"""
    if ship_id not in ships_db:
        raise HTTPException(status_code=404, detail=f"Ship {ship_id} not found")
    if harbor_id not in harbors_db:
        raise HTTPException(status_code=404, detail=f"Harbor {harbor_id} not found")
    
    ship = ships_db[ship_id]
    ship.status = ShipStatus.ANCHORED
    ship.harbor = harbor_id
    
    return {
        "status": "anchored",
        "ship": ship,
        "message": f"⚓ {ship.name} anchored at {harbor_id}"
    }

@app.delete("/ships/{ship_id}")
async def scuttle_ship(ship_id: str):
    """Remove a ship from the fleet (like kubectl delete pod)"""
    if ship_id not in ships_db:
        raise HTTPException(status_code=404, detail=f"Ship {ship_id} not found")
    
    ship = ships_db.pop(ship_id)
    SHIPS_ACTIVE.set(len([s for s in ships_db.values() if s.status != ShipStatus.WRECKED]))
    
    return {
        "status": "scuttled",
        "ship_id": ship_id,
        "message": f"⚰️ {ship.name} has been scuttled and removed from the fleet"
    }

# ============ Voyage Log (like Events) ============

@app.get("/voyages")
async def list_voyages():
    """List all recorded voyages (Kubernetes Events)"""
    return {
        "total_voyages": len(voyages_log),
        "voyages": voyages_log[-10:] if voyages_log else []  # Last 10
    }

# ============ Deployment Summary (like kubectl get all) ============

@app.get("/fleet/summary")
async def fleet_summary():
    """Get a summary of the entire fleet"""
    ships_sailing = [s for s in ships_db.values() if s.status == ShipStatus.SAILING]
    ships_docked = [s for s in ships_db.values() if s.status == ShipStatus.DOCKED]
    ships_anchored = [s for s in ships_db.values() if s.status == ShipStatus.ANCHORED]
    
    total_crew = sum(s.crew_size for s in ships_db.values())
    
    return {
        "fleet_commander": "⚓ Fleet Commander v1.0",
        "total_ships": len(ships_db),
        "ships_sailing": len(ships_sailing),
        "ships_docked": len(ships_docked),
        "ships_anchored": len(ships_anchored),
        "total_crew": total_crew,
        "harbors": len(harbors_db),
        "voyages_completed": len(voyages_log),
        "ship_names": [s.name for s in ships_db.values()]
    }
