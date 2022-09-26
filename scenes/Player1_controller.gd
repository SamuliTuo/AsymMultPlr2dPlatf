extends KinematicBody2D

export var _allowDoubleJump = false
export var _allowDash = true

var RawMovement : Vector2
var Grounded : bool
var input : FrameInput
var _velocity : Vector2
var _lastPos : Vector2
var _currentHorizSpd : float
var _currentVertiSpd : float
var _timeLeftGrounded : int

signal OnDashingChanged(state)
var _dashing : bool
var _dashToConsume : bool
var _jumpToConsume : bool
var _coyoteUsable : bool

var _executedBufferedJump : bool
var _doubleJumpUsable : bool
var _canDash : bool

signal OnJumping()
signal OnDoubleJumping()
export var _jumpHeight = 30.0
export var _jumpApexThreshold = 10.0
export var _coyoteTimeThreshold = int(7)
export var _jumpBuffer = int(7)
export var _jumpEndEarlyGravityModifier = 3
var _endedJumpEarly = true
var _apexPoint : float
var _lastJumpPressed = int(1)
var _fixedFrame : int

func CanUseCoyote() -> bool:
	if _coyoteUsable && !_grounded && _timeLeftGrounded + _coyoteTimeThreshold > _fixedFrame:
		return true
	return false
func HasBufferedJump() -> bool:
	if (_grounded || _cornerStuck) && _lastJumpPressed + _jumpBuffer > _fixedFrame && !_executedBufferedJump:
		return true
	return false
func CanDoubleJump() -> bool:
	if _allowDoubleJump && _doubleJumpUsable && !_coyoteUsable:
		return true
	return false

######################################################################

func _ready():
	_lastPos = Vector2.ZERO
	GatherInput()

func _process(delta):
	var v = (position - _lastPos) / delta
	if v != Vector2.ZERO:
		_velocity = (position - _lastPos) / delta
	_lastPos = position
	
	GatherInput()

func _physics_process(delta):
	_fixedFrame += 1

	RunCollisionChecks()
	
	CalculateWalk(delta)
	CalculateJumpApex()
	CalculateGravity(delta)
	CalculateJump()
	CalculateDash()
	MoveCharacter(delta)

######################################################################

func GatherInput():
	input = FrameInput.new(
		Input.get_action_raw_strength("Plr1_right") - Input.get_action_raw_strength("Plr1_left"),
		Input.get_action_raw_strength("Plr1_up") - Input.get_action_raw_strength("Plr1_down"),
		Input.is_action_just_pressed("Plr1_jump"),
		Input.is_action_pressed("Plr1_jump"),
		Input.is_action_just_pressed("Plr1_dash")
	)
	if (Input.is_action_just_pressed("Plr1_dash")):
		_dashToConsume = true
	if (Input.is_action_just_pressed("Plr1_jump")):
		_lastJumpPressed = _fixedFrame
		_jumpToConsume = true

class FrameInput:
	var X : float
	var Y : float
	var JumpDown : bool
	var JumpHeld : bool
	var DashDown : bool
	
	func _init(_X:float, _Y:float, _JumpDown:bool, _JumpHeld:bool, _DashDown:bool):
		X = _X
		Y = _Y
		JumpDown = _JumpDown
		JumpHeld = _JumpHeld
		DashDown = _DashDown

class RayRange:
	var Start : Vector2
	var End : Vector2
	var dir : Vector2
	func _init(x1:float, y1:float, x2:float, y2:float, _dir:Vector2):
		Start = Vector2(x1, y1)
		End = Vector2(x2, y2)
		dir = _dir
	var ray = [Start, End, dir] setget ray_set, ray_get	
	func ray_get():
		return ray
	func ray_set(_ray):
		ray = _ray

# Collisions
signal OnGroundedChanged(state)
export var _detectorCount = 3
export var _detectionRayLength = 0.1

var _raysUp : RayRange
var _raysRight : RayRange
var _raysDown : RayRange
var _raysLeft : RayRange

var _hittingCeiling : bool
var _grounded : bool
var _colRight : bool
var _colLeft : bool

func RunCollisionChecks():
	CalculateRayRanges()
	
	var groundedCheck = RunDetection(_raysDown)
	if (_grounded && !groundedCheck):
		_timeLeftGrounded = _fixedFrame
		emit_signal("OnGroundedChanged", false)
	elif (!_grounded && groundedCheck):
		_coyoteUsable = true
		_executedBufferedJump = false
		_doubleJumpUsable = true
		_canDash = true
		emit_signal("OnGroundedChanged", true)
	
	_grounded = groundedCheck
	_colLeft = RunDetection(_raysLeft)
	_colRight = RunDetection(_raysRight)
	_hittingCeiling = RunDetection(_raysUp)

func RunDetection(rayRange : RayRange) -> bool:
	var space_state = get_world_2d().direct_space_state
	var rays = EvaluateRayPositions(rayRange)
	for i in range(rays.size()):
		var result = space_state.intersect_ray(
			global_position + rays[i], 
			global_position + rays[i] + rayRange.dir * _detectionRayLength, 
			[self], collision_layer, true, true)
		if result.size() > 0:
			return true
	return false

func CalculateRayRanges():
	var b = $CollisionShape2D.get_shape().extents
	_raysDown = RayRange.new(-b.x, b.y, b.x, b.y, Vector2.DOWN)
	_raysUp = RayRange.new(-b.x, -b.y, b.x, -b.y, Vector2.UP)
	_raysLeft = RayRange.new(-b.x, b.y, -b.x, -b.y, Vector2.LEFT)
	_raysRight = RayRange.new(b.x, b.y, b.x, -b.y, Vector2.RIGHT)
	
func EvaluateRayPositions(rayRange:RayRange) -> Array:
	var out = []
	for i in range(_detectorCount):
		var t = float(i) / (_detectorCount - 1)
		out.append(rayRange.Start.linear_interpolate(rayRange.End, t))
	return out


# Walking
export var _acceleration = 90.0
export var _moveClamp = 13.0
export var _deAcceleration = 60.0
export var _apexBonus = 2.0

func CalculateWalk(_delta):
	if input == null:
		return
	
	if (input.X != 0):
		# Set horizontal move speed
		_currentHorizSpd += input.X * _acceleration * _delta
		# clamped by max free movement
		_currentHorizSpd = clamp(_currentHorizSpd, -_moveClamp, _moveClamp)
		
		
		# Apply bonus at the apex of a jump
		var apexBonus = sign(input.X) * _apexBonus * _apexPoint
		_currentHorizSpd += apexBonus * _delta
	else:
		# No input, decelerate
		_currentHorizSpd = move_toward(_currentHorizSpd, 0, _deAcceleration * _delta)
	
	if (_currentHorizSpd > 0 && _colRight || _currentHorizSpd < 0 && _colLeft):
		# Don't pile up useless horizontal
		_currentHorizSpd = 0

# Gravity
export var _fallClamp = -40.0
export var _minFallSpeed = 80.0
export var _maxFallSpeed = 120.0
var _fallSpeed : float

func CalculateGravity(_delta):
	if _grounded:
		# Move out of the ground
		if _currentVertiSpd > 0:
			_currentVertiSpd = 0
	else:
		var fallSpeed
		# Add downward force while ascending if we ended the jump early
		if _endedJumpEarly && _currentVertiSpd < 0:
			fallSpeed = _fallSpeed * _jumpEndEarlyGravityModifier
		else:
			fallSpeed = _fallSpeed
		
		# Fall
		_currentVertiSpd += fallSpeed * _delta
		
		# Clamp
		if (_currentVertiSpd > _fallClamp):
			_currentVertiSpd = _fallClamp

# Jump
func CalculateJumpApex():
	if !_grounded:
		# Gets stronger the closer to the top of the jump
		_apexPoint = inverse_lerp(0, _jumpApexThreshold, abs(_velocity.y))
		_apexPoint = clamp(_apexPoint, 0, 1)
		_fallSpeed = lerp(_minFallSpeed, _maxFallSpeed, _apexPoint)
	else:
		_apexPoint = 0

func CalculateJump():
	if _jumpToConsume && CanDoubleJump():
		_currentVertiSpd = -_jumpHeight
		_doubleJumpUsable = false
		_endedJumpEarly = false
		_jumpToConsume = false
		print("jump1")
		emit_signal("OnDoubleJumping")
	
	# Jump if: grounded or withing coyote-time || sufficient jump buffer
	if (_jumpToConsume && CanUseCoyote()) || HasBufferedJump():
		_currentVertiSpd = -_jumpHeight
		_endedJumpEarly = false
		_coyoteUsable = false
		_jumpToConsume = false
		_timeLeftGrounded = _fixedFrame
		_executedBufferedJump = true
		print("jump2")
		emit_signal("OnJumping")
	
	# End the jump early if button released
	if !_grounded && !input.JumpHeld && !_endedJumpEarly && _velocity.y < 0:
		_endedJumpEarly = true
	
	if _hittingCeiling && _currentVertiSpd < 0:
		print("ceilinged")
		_currentVertiSpd = 0
		pass


# Dash
export var _dashPower = 50
export var _dashLength = 3
export var _dashEndHorizontalMultiplier = 0.25
var _startedDashing : float
#var _canDash : bool
var _dashVelo : Vector2

#var _dashing : bool
#var _dashToConsume : bool

func CalculateDash():
	if (!_allowDash): 
		return
	if (_dashToConsume && _canDash):
		_dashToConsume = false
		var vel
		if _grounded && input.Y < 0: 
			vel = Vector2(input.X, 0)
		else: 
			vel = Vector2(input.X, input.Y)
		if vel == Vector2.ZERO: return
		_dashVelo = vel * _dashPower
		_dashing = true
		emit_signal("OnDashingChanged", true)
		_canDash = false
		_startedDashing = _fixedFrame
	
	if (_dashing):
		_currentHorizSpd = _dashVelo.x
		_currentVertiSpd = _dashVelo.y
		# Cancel when the time is out or we've reached our max safety distance
		if (_startedDashing + _dashLength < _fixedFrame):
			_dashing = false
			emit_signal("OnDashingChanged", false)
			_currentVertiSpd = 0
			_currentHorizSpd *= _dashEndHorizontalMultiplier
			if (_grounded):
				_canDash = true

		#void CalculateDash() {
		#    if (!_allowDash) return;
		#    if (_dashToConsume && _canDash) {
		#        _dashToConsume = false;
		#        var vel = new Vector2(Input.X, _grounded && Input.Y < 0 ? 0 : Input.Y);
		#        if (vel == Vector2.zero) return;
		#        _dashVel = vel * _dashPower;
		#        _dashing = true;
		#        OnDashingChanged?.Invoke(true);
		#        _canDash = false;
		#        _startedDashing = _fixedFrame;
		#    }

		#    if (_dashing) {
		#        _currentHorizontalSpeed = _dashVel.x;
		#        _currentVerticalSpeed = _dashVel.y;
		#        // Cancel when the time is out or we've reached our max safety distance
		#        if (_startedDashing + _dashLength < _fixedFrame) {
		#            _dashing = false;
		#            OnDashingChanged?.Invoke(false);
		#            _currentVerticalSpeed = 0;
		#            _currentHorizontalSpeed *= _dashEndHorizontalMultiplier;
		#            if (_grounded) _canDash = true;
		#        }
		#    }
		#}

# Move
func MoveCharacter(_delta):
	RawMovement = Vector2(_currentHorizSpd, _currentVertiSpd)
	var move = RawMovement * _delta
	
	move = move_and_slide(RawMovement, Vector2.UP)
	RunCornerPrevention()

#Corner stuck prevention
var _lastPosition : Vector2
var _cornerStuck : bool

func RunCornerPrevention():
	_cornerStuck = !_grounded && _lastPosition == global_position && _lastJumpPressed + 1 < _fixedFrame
	if _cornerStuck:
		print("cornerStruck")
		_currentVertiSpd = 0
	
	_lastPosition = global_position
	
	#_cornerStuck = !_grounded && _lastPos == _rb.position && _lastJumpPressed + 1 < _fixedFrame;
	#_currentVerticalSpeed = _cornerStuck ? 0 : _currentVerticalSpeed;
	#_lastPos = _rb.position;
	
	
	
	
