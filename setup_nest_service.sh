#!/bin/bash

# Update package lists
echo "Updating package lists..."
sudo apt update

# Remove any existing Node.js installation and conflicting packages
echo "Removing old Node.js and conflicting packages..."
sudo apt remove -y nodejs libnode-dev
sudo apt autoremove -y

# Install curl if not already installed
echo "Installing curl..."
sudo apt install -y curl

# Install Node.js and npm (latest stable version)
echo "Installing Node.js and npm..."
curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Reload the shell to update PATH (run in non-root shell)
export PATH=$PATH:/usr/local/bin

# Check versions to ensure correct installation
node -v
npm -v

# Clean npm cache and reinstall NestJS CLI
echo "Cleaning npm cache..."
npm cache clean --force

echo "Reinstalling NestJS CLI..."
sudo npm install -g @nestjs/cli

# Install PostgreSQL
echo "Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# Start PostgreSQL service
echo "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create a new PostgreSQL user and database if they do not exist
DB_USER="nest_user"
DB_PASSWORD="nest_password"
DB_NAME="nest_db"

echo "Creating PostgreSQL user and database if not exist..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

# Remove existing project directory if it exists
PROJECT_NAME="user-service"
if [ -d "$PROJECT_NAME" ]; then
  echo "Removing existing project directory..."
  rm -rf $PROJECT_NAME
fi

# Create a new NestJS project
echo "Creating a new NestJS project..."
nest new $PROJECT_NAME --skip-install

# Ensure the project was created successfully
if [ ! -d "$PROJECT_NAME" ]; then
  echo "Error: NestJS project directory $PROJECT_NAME was not created."
  exit 1
fi

# Change to the project directory
cd $PROJECT_NAME

# Install required dependencies
echo "Installing dependencies..."
npm install

# Install necessary packages for PostgreSQL and TypeORM
echo "Installing TypeORM and PostgreSQL packages..."
npm install @nestjs/typeorm typeorm pg

# Remove existing files to prevent merge conflicts
if [ -f "src/user/user.module.ts" ]; then
  echo "Removing existing src/user/user.module.ts..."
  rm -f src/user/user.module.ts
fi

if [ -f "src/user/user.service.ts" ]; then
  echo "Removing existing src/user/user.service.ts..."
  rm -f src/user/user.service.ts
fi

if [ -f "src/user/user.controller.ts" ]; then
  echo "Removing existing src/user/user.controller.ts..."
  rm -f src/user/user.controller.ts
fi

# Create a new User entity and repository
echo "Generating User entity and repository..."
nest generate module user --no-spec
nest generate service user --no-spec
nest generate controller user --no-spec

# Ensure directories exist before creating files
mkdir -p src/user

# Define User entity in `src/user/user.entity.ts`
cat > src/user/user.entity.ts <<EOL
import { Entity, Column, PrimaryGeneratedColumn } from 'typeorm';

@Entity()
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  firstName: string;

  @Column()
  lastName: string;

  @Column()
  age: number;

  @Column()
  gender: string;

  @Column({ default: false })
  hasProblems: boolean;
}
EOL

# Update `src/user/user.module.ts` to import TypeOrmModule and register User entity
cat > src/user/user.module.ts <<EOL
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserService } from './user.service';
import { UserController } from './user.controller';
import { User } from './user.entity';

@Module({
  imports: [TypeOrmModule.forFeature([User])],
  providers: [UserService],
  controllers: [UserController],
})
export class UserModule {}
EOL

# Set up TypeORM in `src/app.module.ts`
cat > src/app.module.ts <<EOL
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserModule } from './user/user.module';
import { User } from './user/user.entity';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: 'localhost',
      port: 5432,
      username: '$DB_USER',
      password: '$DB_PASSWORD',
      database: '$DB_NAME',
      entities: [User],
      synchronize: true,
    }),
    UserModule,
  ],
})
export class AppModule {}
EOL

# Update `src/user/user.service.ts` with required logic
cat > src/user/user.service.ts <<EOL
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './user.entity';

@Injectable()
export class UserService {
  constructor(
    @InjectRepository(User)
    private userRepository: Repository<User>,
  ) {}

  async setProblemsFlagToFalseAndCountTrue(): Promise<number> {
    const count = await this.userRepository.count({ where: { hasProblems: true } });
    await this.userRepository.update({ hasProblems: true }, { hasProblems: false });
    return count;
  }

  async seedUsers(): Promise<void> {
    for (let i = 0; i < 1000000; i++) {
      const user = this.userRepository.create({
        firstName: 'FirstName' + i,
        lastName: 'LastName' + i,
        age: Math.floor(Math.random() * 100),
        gender: i % 2 === 0 ? 'Male' : 'Female',
        hasProblems: Math.random() < 0.5,
      });
      await this.userRepository.save(user);
    }
  }
}
EOL

# Update `src/user/user.controller.ts` with required endpoint
cat > src/user/user.controller.ts <<EOL
import { Controller, Post } from '@nestjs/common';
import { UserService } from './user.service';

@Controller('user')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Post('reset-problems')
  async resetProblems() {
    const count = await this.userService.setProblemsFlagToFalseAndCountTrue();
    return { message: 'Problems flag reset', usersWithProblems: count };
  }

  @Post('seed')
  async seedUsers() {
    await this.userService.seedUsers();
    return { message: 'Users seeded successfully' };
  }
}
EOL

# Run the NestJS application
echo "Running NestJS application..."
npm run start
