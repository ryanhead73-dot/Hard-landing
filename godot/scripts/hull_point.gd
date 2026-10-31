class_name HullPoint
extends Node3D
## A spot on Kestrel's hull the wildlife attacks during a siege. Damage goes to the siege's hull.

var siege: ShipSiege


func take_damage(amount: float, _from: Vector3 = Vector3.ZERO) -> bool:
	siege.damage_hull(amount)
	return false
