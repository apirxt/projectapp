import React, { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectItem } from "@/components/ui/select";
import { Table } from "@/components/ui/table";

const AdminDashboard = () => {
    const [users, setUsers] = useState([
        { id: 1, name: "User A", role: "User" },
        { id: 2, name: "User B", role: "Admin" },
    ]);
    const [selectedUser, setSelectedUser] = useState(null);
    const [role, setRole] = useState("");

    const updateUserRole = (id, newRole) => {
        setUsers(users.map(user => (user.id === id ? { ...user, role: newRole } : user)));
    };

    return (
        <div className="p-6">
            <h1 className="text-xl font-bold mb-4">Admin Dashboard</h1>
            <Card>
                <CardContent>
                    <Table>
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Role</th>
                                <th>Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            {users.map((user) => (
                                <tr key={user.id}>
                                    <td>{user.name}</td>
                                    <td>{user.role}</td>
                                    <td>
                                        <Select onValueChange={(value) => setRole(value)}>
                                            <SelectItem value="User">User</SelectItem>
                                            <SelectItem value="Admin">Admin</SelectItem>
                                        </Select>
                                        <Button onClick={() => updateUserRole(user.id, role)}>Update</Button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </Table>
                </CardContent>
            </Card>
        </div>
    );
};

export default AdminDashboard;
